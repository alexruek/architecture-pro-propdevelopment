#!/bin/bash
# verify-admission.sh
# Проверяет, что небезопасные поды отклоняются, а безопасные - принимаются

NAMESPACE="audit-zone"
PASS=0
FAIL=0

log_result() {
  local status=$1
  local message=$2
  if [ "$status" -eq 0 ]; then
    echo "[PASS] $message"
    PASS=$((PASS + 1))
  else
    echo "[FAIL] $message"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Проверка блокировки небезопасных подов ==="
echo ""

# Тест 1: привилегированный под должен быть отклонен
echo "--- Тест 1: privileged pod ---"
kubectl apply -f ../insecure-manifests/01-privileged-pod.yaml 2>&1 | grep -q "forbidden\|Error\|violat"
log_result $? "Privileged pod отклонен admission controller"
kubectl delete pod pod-privileged -n $NAMESPACE --ignore-not-found=true > /dev/null 2>&1

# Тест 2: hostPath под должен быть отклонен
echo "--- Тест 2: hostPath pod ---"
kubectl apply -f ../insecure-manifests/02-hostpath-pod.yaml 2>&1 | grep -q "forbidden\|Error\|violat"
log_result $? "HostPath pod отклонен admission controller"
kubectl delete pod pod-hostpath -n $NAMESPACE --ignore-not-found=true > /dev/null 2>&1

# Тест 3: root user под должен быть отклонен
echo "--- Тест 3: root user pod ---"
kubectl apply -f ../insecure-manifests/03-root-user-pod.yaml 2>&1 | grep -q "forbidden\|Error\|violat"
log_result $? "Root user pod отклонен admission controller"
kubectl delete pod pod-root-user -n $NAMESPACE --ignore-not-found=true > /dev/null 2>&1

echo ""
echo "=== Проверка принятия безопасных подов ==="
echo ""

# Тест 4: безопасный под 01 должен пройти
echo "--- Тест 4: secure pod 01 ---"
kubectl apply -f ../secure-manifests/01-secure.yaml > /dev/null 2>&1
log_result $? "Secure pod 01 принят"
kubectl delete pod pod-secure-01 -n $NAMESPACE --ignore-not-found=true > /dev/null 2>&1

# Тест 5: безопасный под 02 должен пройти
echo "--- Тест 5: secure pod 02 ---"
kubectl apply -f ../secure-manifests/02-secure.yaml > /dev/null 2>&1
log_result $? "Secure pod 02 принят"
kubectl delete pod pod-secure-02 -n $NAMESPACE --ignore-not-found=true > /dev/null 2>&1

# Тест 6: безопасный под 03 должен пройти
echo "--- Тест 6: secure pod 03 ---"
kubectl apply -f ../secure-manifests/03-secure.yaml > /dev/null 2>&1
log_result $? "Secure pod 03 принят"
kubectl delete pod pod-secure-03 -n $NAMESPACE --ignore-not-found=true > /dev/null 2>&1

echo ""
echo "=== Итог ==="
echo "Пройдено: $PASS / $((PASS + FAIL))"
echo "Провалено: $FAIL / $((PASS + FAIL))"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
