#!/bin/bash

# Пользователь 1: viewer
openssl genrsa -out viewer.key 2048
openssl req -new -key viewer.key -out viewer.csr -subj "/CN=viewer/O=readonly-users"
openssl x509 -req -in viewer.csr -CA ~/.minikube/ca.crt -CAkey ~/.minikube/ca.key \
  -CAcreateserial -out viewer.crt -days 365

kubectl config set-credentials viewer \
  --client-certificate=viewer.crt \
  --client-key=viewer.key

kubectl config set-context viewer-context \
  --cluster=minikube \
  --user=viewer

# Пользователь 2: operator
openssl genrsa -out operator.key 2048
openssl req -new -key operator.key -out operator.csr -subj "/CN=operator/O=operators"
openssl x509 -req -in operator.csr -CA ~/.minikube/ca.crt -CAkey ~/.minikube/ca.key \
  -CAcreateserial -out operator.crt -days 365

kubectl config set-credentials operator \
  --client-certificate=operator.crt \
  --client-key=operator.key

kubectl config set-context operator-context \
  --cluster=minikube \
  --user=operator