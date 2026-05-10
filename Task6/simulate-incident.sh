#!/bin/bash
# simulate-incident.sh - симуляция подозрительных действий согласно заданию

set -e

echo "=== Симуляция инцидента ==="

kubectl create ns secure-ops 2>/dev/null || echo "Namespace уже существует"
kubectl config set-context --current --namespace=secure-ops
kubectl create sa monitoring 2>/dev/null || echo "SA уже существует"
kubectl run attacker-pod --image=alpine --command -- sleep 3600 2>/dev/null || echo "Pod уже существует"

echo "[1] Разведка - проверка прав SA monitoring..."
kubectl auth can-i get secrets --as=system:serviceaccount:secure-ops:monitoring || true

echo "[2] Чтение системных секретов от имени SA monitoring..."
SECRET=$(kubectl get secrets -n kube-system 2>/dev/null | awk 'NR==2{print $1}')
[ -n "$SECRET" ] && kubectl get secret "$SECRET" -n kube-system \
  --as=system:serviceaccount:secure-ops:monitoring 2>/dev/null || true

echo "[3] Создание привилегированного пода..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: privileged-pod
  namespace: secure-ops
spec:
  containers:
  - name: pwn
    image: alpine
    command: ["sleep", "3600"]
    securityContext:
      privileged: true
  restartPolicy: Never
EOF

echo "[4] Exec в системный под..."
SYSPOD=$(kubectl get pods -n kube-system 2>/dev/null | awk 'NR==2{print $1}')
[ -n "$SYSPOD" ] && kubectl exec -n kube-system "$SYSPOD" -- cat /etc/resolv.conf 2>/dev/null || true

echo "[5] Попытка удалить audit-policy..."
kubectl delete configmap audit-policy -n kube-system --as=admin 2>/dev/null || true

echo "[6] Создание RoleBinding с cluster-admin..."
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: escalate-binding
  namespace: secure-ops
subjects:
- kind: ServiceAccount
  name: monitoring
  namespace: secure-ops
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

echo ""
echo "=== Готово ==="
echo "Получите лог:"
echo "  minikube ssh 'sudo cat /var/log/audit/audit.log' > audit.log"
