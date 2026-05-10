#!/usr/bin/env python3
"""
filter_audit.py - фильтрация подозрительных событий из Kubernetes audit.log

Использование:
    python3 filter_audit.py [audit.log] [-o audit-extract.json] [--only-allowed]

Аргументы:
    audit.log         путь к файлу лога (по умолчанию: audit.log)
    -o, --output      выходной файл (по умолчанию: audit-extract.json)
    --only-allowed    фильтровать только разрешенные действия (allow)

Категории подозрительных событий:
    secrets_access          - чтение secrets
    exec_into_pod           - kubectl exec в под
    privileged_pod          - создание привилегированного пода
    rolebinding_escalation  - создание RoleBinding с admin-правами
    audit_tampering         - попытка удалить или изменить audit-policy
"""

import json
import sys
import argparse
from collections import defaultdict


CATEGORIES = {
    "secrets_access": "Доступ к secrets",
    "exec_into_pod": "Использование exec в поде",
    "privileged_pod": "Создание привилегированного пода",
    "rolebinding_escalation": "Создание RoleBinding (возможная эскалация)",
    "audit_tampering": "Попытка изменить или удалить audit-policy",
}

HIGH_PRIVILEGE_ROLES = {
    "cluster-admin",
    "admin",
    "edit",
    "system:masters",
}


# --- Функции проверки по категориям ---

def check_secrets_access(event):
    obj = event.get("objectRef", {})
    return (
        obj.get("resource") == "secrets"
        and event.get("verb") in ("get", "list", "watch")
    )


def check_exec_into_pod(event):
    obj = event.get("objectRef", {})
    return (
        event.get("verb") == "create"
        and obj.get("resource") == "pods"
        and obj.get("subresource") == "exec"
    )


def check_privileged_pod(event):
    obj = event.get("objectRef", {})
    if obj.get("resource") != "pods":
        return False
    if event.get("verb") not in ("create", "update", "patch"):
        return False
    req = event.get("requestObject") or {}
    spec = req.get("spec") or {}
    all_containers = (
        spec.get("containers", [])
        + spec.get("initContainers", [])
        + spec.get("ephemeralContainers", [])
    )
    for container in all_containers:
        sc = container.get("securityContext") or {}
        if sc.get("privileged") is True:
            return True
    # hostPath volumes
    for vol in spec.get("volumes", []):
        if "hostPath" in vol:
            return True
    return False


def check_rolebinding_escalation(event):
    obj = event.get("objectRef", {})
    resource = obj.get("resource", "")
    if resource not in ("rolebindings", "clusterrolebindings"):
        return False
    if event.get("verb") not in ("create", "update", "patch"):
        return False
    req = event.get("requestObject") or {}
    role_ref = req.get("roleRef") or {}
    role_name = role_ref.get("name", "")
    return role_name in HIGH_PRIVILEGE_ROLES


def check_audit_tampering(event):
    obj = event.get("objectRef", {})
    name = (obj.get("name") or "").lower()
    uri = event.get("requestURI", "").lower()
    is_destructive = event.get("verb") in ("delete", "update", "patch", "deletecollection")
    mentions_audit = "audit" in name or "audit-policy" in uri or "audit-policy" in name
    return is_destructive and mentions_audit


CHECKS = {
    "secrets_access": check_secrets_access,
    "exec_into_pod": check_exec_into_pod,
    "privileged_pod": check_privileged_pod,
    "rolebinding_escalation": check_rolebinding_escalation,
    "audit_tampering": check_audit_tampering,
}


# --- Вспомогательные функции ---

def _safe_check(fn, event):
    try:
        return fn(event)
    except Exception:
        return False


def classify(event):
    return [name for name, fn in CHECKS.items() if _safe_check(fn, event)]


def make_summary(event):
    return {
        "user": event.get("user", {}).get("username", "unknown"),
        "impersonated_user": event.get("impersonatedUser", {}).get("username"),
        "verb": event.get("verb"),
        "resource": event.get("objectRef", {}).get("resource"),
        "subresource": event.get("objectRef", {}).get("subresource"),
        "namespace": event.get("objectRef", {}).get("namespace"),
        "name": event.get("objectRef", {}).get("name"),
        "response_code": event.get("responseStatus", {}).get("code"),
        "decision": event.get("annotations", {}).get(
            "authorization.k8s.io/decision"
        ),
        "timestamp": event.get("requestReceivedTimestamp"),
    }


def enrich(event, categories):
    result = dict(event)
    result["_suspicious_categories"] = categories
    result["_descriptions"] = [CATEGORIES[c] for c in categories]
    result["_summary"] = make_summary(event)
    return result


def parse_log(path):
    events, skipped = [], 0
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                skipped += 1
    if skipped:
        print(
            f"[warn] Пропущено строк с ошибкой JSON: {skipped}",
            file=sys.stderr,
        )
    return events


def print_summary(suspicious, total):
    counts = defaultdict(int)
    for e in suspicious:
        for c in e.get("_suspicious_categories", []):
            counts[c] += 1

    print(f"\nВсего событий в логе:   {total}")
    print(f"Подозрительных событий: {len(suspicious)}")
    print("\nПо категориям:")
    for key, label in CATEGORIES.items():
        print(f"  {label:<48} {counts[key]:>4}")
    print()


def print_event_table(suspicious):
    print(f"{'Время':<28} {'Пользователь':<45} {'Действие':<10} {'Ресурс':<15} {'Namespace':<15} {'Категория'}")
    print("-" * 140)
    for e in suspicious:
        s = e["_summary"]
        cats = ", ".join(e.get("_suspicious_categories", []))
        ts = (s.get("timestamp") or "")[:26]
        user = (s.get("user") or "")[:44]
        verb = (s.get("verb") or "")[:9]
        resource = (s.get("resource") or "")[:14]
        ns = (s.get("namespace") or "")[:14]
        print(f"{ts:<28} {user:<45} {verb:<10} {resource:<15} {ns:<15} {cats}")


# --- Точка входа ---

def main():
    parser = argparse.ArgumentParser(
        description="Фильтрация подозрительных событий из Kubernetes audit.log"
    )
    parser.add_argument(
        "log_file",
        nargs="?",
        default="audit.log",
        help="Путь к audit.log (по умолчанию: audit.log)",
    )
    parser.add_argument(
        "-o", "--output",
        default="audit-extract.json",
        help="Выходной JSON-файл (по умолчанию: audit-extract.json)",
    )
    parser.add_argument(
        "--only-allowed",
        action="store_true",
        help="Показывать только события с решением allow",
    )
    parser.add_argument(
        "--table",
        action="store_true",
        help="Вывести таблицу событий в stdout",
    )
    args = parser.parse_args()

    print(f"Читаю лог: {args.log_file}")
    events = parse_log(args.log_file)

    suspicious = []
    for e in events:
        if args.only_allowed:
            decision = e.get("annotations", {}).get(
                "authorization.k8s.io/decision"
            )
            if decision != "allow":
                continue
        cats = classify(e)
        if cats:
            suspicious.append(enrich(e, cats))

    print_summary(suspicious, len(events))

    if args.table and suspicious:
        print_event_table(suspicious)
        print()

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(suspicious, f, ensure_ascii=False, indent=2)

    print(f"Результат записан: {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
