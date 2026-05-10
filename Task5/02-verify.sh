#!/bin/bash
# =============================================================================
# Проверка сетевых политик
# Тестирует разрешенные и запрещенные маршруты трафика
# =============================================================================

set -uo pipefail

NAMESPACE="prop-network"
TIMEOUT=3
PASS=0
FAIL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "============================================"
echo " Task 5 — Проверка сетевых политик"
echo " Namespace: ${NAMESPACE}"
echo "============================================"
echo ""

# Тест разрешенного соединения
test_allowed() {
  local source_label="$1"
  local target_svc="$2"
  local test_name="$3"

  result=$(kubectl run "test-allow-${RANDOM}" \
    --rm -i \
    --image=alpine \
    --labels="role=${source_label}" \
    -n "${NAMESPACE}" \
    --restart=Never \
    --quiet \
    -- wget -qO- --timeout=${TIMEOUT} "http://${target_svc}" 2>&1 || true)

  if echo "${result}" | grep -q "Welcome to nginx"; then
    echo -e "${GREEN}✅ PASS${NC} [РАЗРЕШЕНО] ${test_name}"
    ((PASS++))
  else
    echo -e "${RED}❌ FAIL${NC} [РАЗРЕШЕНО] ${test_name} — трафик заблокирован (ожидался ответ nginx)"
    ((FAIL++))
  fi
}

# Тест запрещенного соединения
test_denied() {
  local source_label="$1"
  local target_svc="$2"
  local test_name="$3"

  result=$(kubectl run "test-deny-${RANDOM}" \
    --rm -i \
    --image=alpine \
    --labels="role=${source_label}" \
    -n "${NAMESPACE}" \
    --restart=Never \
    --quiet \
    -- wget -qO- --timeout=${TIMEOUT} "http://${target_svc}" 2>&1 || true)

  if echo "${result}" | grep -q "wget:"; then
    echo -e "${GREEN}✅ PASS${NC} [ЗАПРЕЩЕНО] ${test_name} — трафик корректно заблокирован"
    ((PASS++))
  elif echo "${result}" | grep -q "Welcome to nginx"; then
    echo -e "${RED}❌ FAIL${NC} [ЗАПРЕЩЕНО] ${test_name} — трафик НЕ заблокирован (политика не работает!)"
    ((FAIL++))
  else
    echo -e "${YELLOW}⚠️ WARN${NC} [ЗАПРЕЩЕНО] ${test_name} — неожиданный ответ: ${result}"
  fi
}

echo "--- Проверка примененных политик ---"
kubectl get networkpolicies -n "${NAMESPACE}"
echo ""

echo "--- Тесты разрешенного трафика ---"
test_allowed "front-end"       "back-end-api-app"       "front-end → back-end-api"
test_allowed "back-end-api"    "front-end-app"           "back-end-api → front-end"
test_allowed "admin-front-end" "admin-back-end-api-app" "admin-front-end → admin-back-end-api"
test_allowed "admin-back-end-api" "admin-front-end-app" "admin-back-end-api → admin-front-end"

echo ""
echo "--- Тесты запрещенного трафика ---"
test_denied "front-end"         "admin-back-end-api-app" "front-end → admin-back-end-api"
test_denied "front-end"         "admin-front-end-app"    "front-end → admin-front-end"
test_denied "back-end-api"      "admin-back-end-api-app" "back-end-api → admin-back-end-api"
test_denied "admin-front-end"   "back-end-api-app"       "admin-front-end → back-end-api"
test_denied "admin-front-end"   "front-end-app"          "admin-front-end → front-end"
test_denied "admin-back-end-api" "back-end-api-app"      "admin-back-end-api → back-end-api"

echo ""
echo "============================================"
echo " Итог: ✅ PASS: ${PASS}  ❌ FAIL: ${FAIL}"
echo "============================================"

if [ "${FAIL}" -gt 0 ]; then
  echo ""
  echo -e "${RED}ВНИМАНИЕ: Есть проблемы с сетевыми политиками!${NC}"
  echo "Убедитесь, что Minikube запущен с поддержкой NetworkPolicy:"
  echo "  minikube start --cni=calico"
  exit 1
else
  echo ""
  echo -e "${GREEN}Все тесты пройдены успешно!${NC}"
  exit 0
fi
