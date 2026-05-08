| Роль              | Группа    | Полномочия                          | Ресурсы                                        |
| --------------------- | --------------- | --------------------------------------------- | ----------------------------------------------------- |
| cluster-admin-role    | platform-admins | `*` (все)                                  | `*` (все)                                          |
| cluster-viewer-role   | readonly-users  | get, list, watch                              | pods, services,<br /> <br />deployments, configmaps   |
| cluster-operator-role | operators       | get, list, watch, <br />create, update, patch | pods, services, deployments,<br />secrets, configmaps |
