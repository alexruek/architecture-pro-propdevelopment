# Привязываем пользователя viewer к cluster-viewer-role
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: viewer-binding
subjects:
- kind: User
  name: viewer          # CN из сертификата
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-viewer-role
  apiGroup: rbac.authorization.k8s.io
EOF

# Привязываем пользователя operator к cluster-operator-role
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: operator-binding
subjects:
- kind: User
  name: operator        # CN из сертификата
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-operator-role
  apiGroup: rbac.authorization.k8s.io
EOF