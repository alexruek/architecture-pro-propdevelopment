#!/bin/bash
# =============================================================================
# Task 5 — PropDevelopment: Развёртывание сервисов в Kubernetes
# Создаёт 4 пода nginx с метками ролей и соответствующие Service
# =============================================================================

set -euo pipefail

NAMESPACE="prop-network"

echo "=== [1/5] Создание namespace ==="
kubectl apply -f 00-namespace.yaml
kubectl config set-context --current --namespace="${NAMESPACE}"
echo "Namespace ${NAMESPACE} готов."

echo ""
echo "=== [2/5] Развёртывание сервисов ==="

# front-end: клиентский фронтенд PropDevelopment (Витрина)
kubectl run front-end-app \
  --image=nginx \
  --labels role=front-end \
  --expose \
  --port 80 \
  -n "${NAMESPACE}" \
  --restart=Never 2>/dev/null || echo "front-end-app уже существует"

# back-end-api: API для клиентских сервисов (client-mart-app, client-tour-app)
kubectl run back-end-api-app \
  --image=nginx \
  --labels role=back-end-api \
  --expose \
  --port 80 \
  -n "${NAMESPACE}" \
  --restart=Never 2>/dev/null || echo "back-end-api-app уже существует"

# admin-front-end: административный фронтенд (CRM-интерфейс)
kubectl run admin-front-end-app \
  --image=nginx \
  --labels role=admin-front-end \
  --expose \
  --port 80 \
  -n "${NAMESPACE}" \
  --restart=Never 2>/dev/null || echo "admin-front-end-app уже существует"

# admin-back-end-api: API административных сервисов (client-crm-app)
kubectl run admin-back-end-api-app \
  --image=nginx \
  --labels role=admin-back-end-api \
  --expose \
  --port 80 \
  -n "${NAMESPACE}" \
  --restart=Never 2>/dev/null || echo "admin-back-end-api-app уже существует"

echo ""
echo "=== [3/5] Ожидание готовности подов ==="
kubectl wait --for=condition=Ready pod \
  -l 'role in (front-end, back-end-api, admin-front-end, admin-back-end-api)' \
  -n "${NAMESPACE}" \
  --timeout=60s

echo ""
echo "=== [4/5] Текущее состояние ==="
echo "--- Pods ---"
kubectl get pods -n "${NAMESPACE}" -o wide

echo ""
echo "--- Services ---"
kubectl get svc -n "${NAMESPACE}"

echo ""
echo "=== [5/5] Готово! Следующий шаг: ==="
echo "kubectl apply -f non-admin-api-allow.yaml"
