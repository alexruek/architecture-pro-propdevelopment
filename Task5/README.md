# Управление трафиком внутри кластера Kubernetes

## Цель

Развернуть 4 сервиса в одном namespace и настроить сетевые политики:

- `front-end` и `back-end-api` - трафик разрешен в обе стороны
- `admin-front-end` и `admin-back-end-api` - трафик разрешен в обе стороны
- Между парами (`front-end` и `admin-back-end-api` и т.д.) - трафик запрещен

---

## Предварительные требования

```bash
# Нужно запустить Minikube
minikube start

# Обязательно включить поддержку NetworkPolicy через Calico, 
# т.к. стандартный Minikube не применяет NetworkPolicy без CNI-плагина
minikube start --cni=calico
# или так
minikube start --network-plugin=cni --cni=calico
```

---

## Структура файлов в папке задания

```
Task5/
├── README.md
├── 00-namespace.yaml               # Создание namespace
├── 01-deploy-services.sh           # Скрипт развертывания сервисов
├── non-admin-api-allow.yaml        # Основной файл сетевых политик
├── 02-verify.sh                    # Скрипт проверки политик
└── architecture.md                 # Описание архитектурного решения
```

---

## 1. Создание Namespace

Применить `00-namespace.yaml`:

```bash
kubectl apply -f 00-namespace.yaml
kubectl config set-context --current --namespace=prop-network
```

---

## 2. Развертывание сервисов

```bash
chmod +x 01-deploy-services.sh
./01-deploy-services.sh
```

или вручную:

```bash
kubectl run front-end-app \
  --image=nginx \
  --labels role=front-end \
  --expose \
  --port 80 \
  -n prop-network

kubectl run back-end-api-app \
  --image=nginx \
  --labels role=back-end-api \
  --expose \
  --port 80 \
  -n prop-network

kubectl run admin-front-end-app \
  --image=nginx \
  --labels role=admin-front-end \
  --expose \
  --port 80 \
  -n prop-network

kubectl run admin-back-end-api-app \
  --image=nginx \
  --labels role=admin-back-end-api \
  --expose \
  --port 80 \
  -n prop-network
```

проверка:

```bash
kubectl get pods -n prop-network -o wide
kubectl get svc -n prop-network
```

---

## 3. Применение сетевых политик

```bash
kubectl apply -f non-admin-api-allow.yaml
```

Проверка примененных политик:

```bash
kubectl get networkpolicies -n prop-network
kubectl describe networkpolicy -n prop-network
```

---

## 4. Проверка политик

```bash
chmod +x 02-verify.sh
./02-verify.sh
```

Или вручную — тест разрешенного трафика (`front-end` → `back-end-api`):

```bash
# Запускаем тестовый под в namespace
kubectl run test-$RANDOM \
  --rm -i -t \
  --image=alpine \
  -n prop-network \
  -- sh

# Внутри пода:
wget -qO- --timeout=2 http://back-end-api-app   # должен вернуть HTML nginx
wget -qO- --timeout=2 http://admin-back-end-api-app  # должен завершиться по таймауту (запрещено)
```

Тест запрещенного трафика (должен вернуть timeout):

```bash
kubectl run test-admin-$RANDOM \
  --rm -i -t \
  --image=alpine \
  -n prop-network \
  --labels role=front-end \
  -- sh

# Внутри пода:
wget -qO- --timeout=2 http://admin-back-end-api-app  # timeout — политика работает
```

---

## Ожидаемый результат


| Источник   | Назначение | Результат |
| ------------------ | -------------------- | ------------------ |
| front-end          | back-end-api         | Разрешено |
| back-end-api       | front-end            | Разрешено |
| admin-front-end    | admin-back-end-api   | Разрешено |
| admin-back-end-api | admin-front-end      | Разрешено |
| front-end          | admin-back-end-api   | Запрещено |
| admin-front-end    | back-end-api         | Запрещено |
| front-end          | admin-front-end      | Запрещено |
| back-end-api       | admin-back-end-api   | Запрещено |

---

## Очистка

```bash
kubectl delete namespace prop-network
```
