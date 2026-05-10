#!/bin/bash
# setup-audit.sh
# 1. Запускает minikube без аудита (работает надежно)
# 2. Копирует policy-файл в /etc/ssl/certs/ (этот путь уже смонтирован в apiserver-поде)
# 3. Патчит kube-apiserver.yaml - добавляет флаги И volume для лога
# 4. Kubelet автоматически перезапускает apiserver с новым манифестом

set -e

POLICY_FILE="audit-policy.yaml"
POLICY_IN_VM="/etc/ssl/certs/audit-policy.yaml"
LOG_DIR_IN_VM="/var/log/audit"
LOG_IN_VM="/var/log/audit/audit.log"
MANIFEST="/etc/kubernetes/manifests/kube-apiserver.yaml"

[ -f "$POLICY_FILE" ] || { echo "ОШИБКА: $POLICY_FILE не найден. Запустите из директории Task6."; exit 1; }

echo "[1/4] Запуск Minikube..."
minikube delete 2>/dev/null || true
minikube start --driver=docker
kubectl get nodes

echo ""
echo "[2/4] Копирование audit-policy.yaml и подготовка директории для лога..."
minikube cp "$POLICY_FILE" "$POLICY_IN_VM"
minikube ssh "sudo mkdir -p $LOG_DIR_IN_VM && sudo chmod 777 $LOG_DIR_IN_VM"
minikube ssh "ls $POLICY_IN_VM" && echo "Файл скопирован."

echo ""
echo "[3/4] Патч kube-apiserver.yaml (флаги + volume для лога)..."
minikube ssh "sudo python3 << 'PYEOF'
import re, sys

MANIFEST   = '$MANIFEST'
POLICY     = '$POLICY_IN_VM'
LOG_DIR    = '$LOG_DIR_IN_VM'
LOG_PATH   = '$LOG_IN_VM'

with open(MANIFEST) as f:
    content = f.read()

if '--audit-policy-file' in content:
    print('Уже пропатчен.')
    sys.exit(0)

lines = content.split('\n')
result = []
flags_added = mount_added = volume_added = False

AUDIT_FLAGS = [
    '    - --audit-policy-file=' + POLICY,
    '    - --audit-log-path='    + LOG_PATH,
    '    - --audit-log-maxage=1',
    '    - --audit-log-maxbackup=1',
    '    - --audit-log-maxsize=100',
]
AUDIT_MOUNT = [
    '    - mountPath: ' + LOG_DIR,
    '      name: audit-log',
]
AUDIT_VOLUME = [
    '  - hostPath:',
    '      path: ' + LOG_DIR,
    '      type: DirectoryOrCreate',
    '    name: audit-log',
]

for line in lines:
    stripped = line.strip()

    if not flags_added and stripped == '- kube-apiserver':
        result.append(line)
        result.extend(AUDIT_FLAGS)
        flags_added = True
        continue

    if not mount_added and re.match(r'^    volumeMounts:\s*$', line):
        result.append(line)
        result.extend(AUDIT_MOUNT)
        mount_added = True
        continue

    if not volume_added and re.match(r'^  volumes:\s*$', line):
        result.append(line)
        result.extend(AUDIT_VOLUME)
        volume_added = True
        continue

    result.append(line)

for name, ok in [('flags', flags_added), ('volumeMount', mount_added), ('volume', volume_added)]:
    if not ok:
        print('ОШИБКА: не найдена точка вставки для', name)
        sys.exit(1)

with open(MANIFEST, 'w') as f:
    f.write('\n'.join(result))

print('Манифест пропатчен: флаги + volumeMount + volume добавлены.')
PYEOF
"

echo ""
echo "[4/4] Ожидание перезапуска apiserver (kubelet перечитывает манифест)..."
for i in $(seq 1 24); do
    sleep 5
    STATUS=$(kubectl get nodes 2>/dev/null | awk '/minikube/{print $2}')
    echo "  попытка $i/24: $STATUS"
    [ "$STATUS" = "Ready" ] && break
done

echo ""
echo "Проверка флагов:"
minikube ssh "ps aux | tr ' ' '\n' | grep -- '--audit'" 2>/dev/null || true

echo ""
echo "Проверка лога (появляется через 10-15 сек после запроса к API):"
sleep 10 && kubectl get pods -A > /dev/null 2>&1 || true
minikube ssh "ls -lh $LOG_IN_VM 2>/dev/null && wc -l $LOG_IN_VM || echo 'Лог пока не создан'"

echo ""
echo "Готово! Следующие шаги:"
echo "  bash simulate-incident.sh"
echo "  minikube ssh 'sudo cat $LOG_IN_VM' > audit.log"
