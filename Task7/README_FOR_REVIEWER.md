# README FOR REVIEWER

## Структура Task7

```
Task7/
+-- 01-create-namespace.yaml        # Namespace с PodSecurity restricted
+-- audit-policy.yaml               # Политика аудита Kubernetes (артефакт)
+-- insecure-manifests/
|   +-- 01-privileged-pod.yaml      # Нарушение: privileged: true
|   +-- 02-hostpath-pod.yaml        # Нарушение: hostPath volume
|   +-- 03-root-user-pod.yaml       # Нарушение: runAsUser: 0
+-- secure-manifests/
|   +-- 01-secure.yaml              # Исправление привилегированного пода
|   +-- 02-secure.yaml              # Исправление hostPath (заменен на emptyDir)
|   +-- 03-secure.yaml              # Исправление запуска от root
+-- gatekeeper/
|   +-- constraint-templates/
|   |   +-- privileged.yaml         # Template: блокировка privileged
|   |   +-- hostpath.yaml           # Template: блокировка hostPath
|   |   +-- runasnonroot.yaml       # Template: runAsNonRoot + readOnlyRootFilesystem
|   +-- constraints/
|       +-- privileged.yaml         # Constraint: применение блокировки privileged
|       +-- hostpath.yaml           # Constraint: применение блокировки hostPath
|       +-- runasnonroot.yaml       # Constraint: применение проверки nonroot
+-- verify/
    +-- verify-admission.sh         # Тест: блокировка плохих / прохождение хороших
    +-- validate-security.sh        # Диагностика состояния Gatekeeper и PodSecurity
```

---

## Требования для воспроизведения

- Minikube >= 1.32 (kubernetes >= 1.25)
- kubectl
- Helm (для установки Gatekeeper)

---

## Порядок воспроизведения

### Шаг 1. Запуск Minikube

Для Task 7 audit-log не требуется. PodSecurity Admission включен по умолчанию начиная с Kubernetes 1.25.

```bash
minikube start --driver=docker
kubectl get nodes
```

Ожидаемый результат: нода в статусе `Ready`.

Файл `audit-policy.yaml` приложен как артефакт с описанием политики аудита.

### Шаг 2. Создать namespace с PodSecurity restricted

```bash
kubectl apply -f 01-create-namespace.yaml
```

Проверить метки:

```bash
kubectl get namespace audit-zone --show-labels
```

Ожидаемый результат: метки `pod-security.kubernetes.io/enforce: restricted`.

### Шаг 3. Убедиться, что небезопасные поды не проходят

```bash
kubectl apply -f insecure-manifests/01-privileged-pod.yaml
# Ожидание: Error ... forbidden
kubectl apply -f insecure-manifests/02-hostpath-pod.yaml
# Ожидание: Error ... forbidden
kubectl apply -f insecure-manifests/03-root-user-pod.yaml
# Ожидание: Error ... forbidden
```

### Шаг 4. Убедиться, что безопасные поды проходят

```bash
kubectl apply -f secure-manifests/01-secure.yaml
kubectl apply -f secure-manifests/02-secure.yaml
kubectl apply -f secure-manifests/03-secure.yaml
kubectl get pods -n audit-zone
```

Очистить после проверки:

```bash
kubectl delete -f secure-manifests/ --ignore-not-found=true
```

### Шаг 5. Установить OPA Gatekeeper

```bash
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update
helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --version 3.14.0
```

Подождать готовности (30-60 секунд):

```bash
kubectl rollout status deployment/gatekeeper-controller-manager \
  -n gatekeeper-system
```

### Шаг 6. Применить ConstraintTemplates

```bash
kubectl apply -f gatekeeper/constraint-templates/privileged.yaml
kubectl apply -f gatekeeper/constraint-templates/hostpath.yaml
kubectl apply -f gatekeeper/constraint-templates/runasnonroot.yaml
```

Подождать 15-20 секунд, затем убедиться, что CRD созданы:

```bash
sleep 20
kubectl get constrainttemplates
```

### Шаг 7. Применить Constraints

```bash
kubectl apply -f gatekeeper/constraints/privileged.yaml
kubectl apply -f gatekeeper/constraints/hostpath.yaml
kubectl apply -f gatekeeper/constraints/runasnonroot.yaml
kubectl get constraints
```

### Шаг 8. Запустить скрипты проверки

```bash
cd verify
chmod +x verify-admission.sh validate-security.sh

bash verify-admission.sh
bash validate-security.sh
```

---

## Что проверяют политики

| Политика | Что блокирует | Уровень применения |
|---|---|---|
| PodSecurity (restricted) | privileged, hostPath, root UID, отсутствие seccompProfile | Namespace |
| K8sBlockPrivileged | securityContext.privileged: true | Gatekeeper Constraint |
| K8sBlockHostPath | volumes.hostPath | Gatekeeper Constraint |
| K8sRequireNonRoot | runAsNonRoot != true, runAsUser == 0, readOnlyRootFilesystem != true | Gatekeeper Constraint |

Небезопасные поды блокируются на уровне PodSecurity Admission до того, как запрос
достигает Gatekeeper webhook - оба механизма активны и дополняют друг друга.

---

## Исправления в secure-manifests

01-secure.yaml (был privileged: true):
- Убрано `privileged: true`, добавлено `privileged: false`
- Добавлены: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`
- Добавлены: `readOnlyRootFilesystem: true`, `capabilities.drop: [ALL]`
- Добавлен `seccompProfile: RuntimeDefault`

02-secure.yaml (был hostPath):
- Том `hostPath` заменен на `emptyDir`
- Добавлен полный блок securityContext в соответствии с restricted profile

03-secure.yaml (был runAsUser: 0):
- Убран `runAsUser: 0`, добавлен `runAsUser: 1000`
- Добавлен `runAsNonRoot: true` на уровне пода
- Добавлены `runAsGroup`, `fsGroup` для корректной работы файловой системы
