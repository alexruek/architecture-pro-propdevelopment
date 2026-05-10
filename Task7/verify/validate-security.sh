#!/bin/bash
# validate-security.sh
# Проверяет статус Gatekeeper и корректность примененных ограничений

echo "=== Проверка OPA Gatekeeper ==="
echo ""

# 1. Проверка, что Gatekeeper запущен
echo "--- Поды Gatekeeper ---"
kubectl get pods -n gatekeeper-system 2>/dev/null
if [ $? -ne 0 ]; then
  echo "[WARN] Gatekeeper не установлен или namespace gatekeeper-system не существует"
fi
echo ""

# 2. Проверка ConstraintTemplates
echo "--- ConstraintTemplates ---"
kubectl get constrainttemplates 2>/dev/null
echo ""

# 3. Проверка Constraints
echo "--- Constraints ---"
kubectl get constraints 2>/dev/null
echo ""

# 4. Детали каждого constraint
echo "--- Статус K8sBlockPrivileged ---"
kubectl describe k8sblockprivileged block-privileged-containers 2>/dev/null | grep -A5 "Status\|Violations\|Total Violations"
echo ""

echo "--- Статус K8sBlockHostPath ---"
kubectl describe k8sblockhostpath block-hostpath-volumes 2>/dev/null | grep -A5 "Status\|Violations\|Total Violations"
echo ""

echo "--- Статус K8sRequireNonRoot ---"
kubectl describe k8srequirenonroot require-non-root-and-readonly 2>/dev/null | grep -A5 "Status\|Violations\|Total Violations"
echo ""

# 5. Проверка PodSecurity на namespace
echo "--- Метки PodSecurity на namespace audit-zone ---"
kubectl get namespace audit-zone -o jsonpath='{.metadata.labels}' 2>/dev/null | python3 -m json.tool 2>/dev/null || \
kubectl get namespace audit-zone --show-labels 2>/dev/null
echo ""

# 6. Проверка audit-policy
echo "--- Файл audit policy ---"
if minikube ssh "ls /etc/kubernetes/audit-policy.yaml" > /dev/null 2>&1; then
  echo "[OK] audit-policy.yaml присутствует в кластере"
else
  echo "[INFO] Проверьте вручную: minikube ssh 'ls /etc/kubernetes/'"
fi
echo ""

echo "=== Проверка завершена ==="
