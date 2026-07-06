### Шаг 1: Подготовка инструментов

Установите основной сканер и авторизуйтесь:

```bash
npm install -g @socketsecurity/cli
socket login

```

### Шаг 2: Создание «Неприступного Прокси»

Создаем папку для защиты и файл-посредник, который будет единственной точкой входа для `npm`.

1. **Создаем папку:**
```bash
mkdir -p ~/.socket-wrapper

```


2. **Создаем прокси-скрипт:**
```bash
nano ~/.socket-wrapper/npm

```


Вставьте этот код (замените `/usr/local/bin/socket` на вывод команды `which socket`):
```bash
#!/bin/bash
# Полный путь к вашему socket бинарнику
SOCKET_PATH=$(which socket)

# Выполняем проверку и установку
exec "$SOCKET_PATH" npm "$@"

```


3. **Делаем его исполняемым:**
```bash
chmod +x ~/.socket-wrapper/npm

```



### Шаг 3: Глобальная изоляция (Блокировка доступа)

Теперь делаем «ход конем»: запрещаем системе использовать оригинальный `npm` напрямую.

1. **Запрещаем авто-скрипты:**
```bash
npm config set ignore-scripts true

```


2. **Блокируем системный npm (физически):**
```bash
chmod -x $(which npm)

```


*(Если у вас есть `npx`, `yarn` или `pnpm`, сделайте `chmod -x` и для них тоже).*

### Шаг 4: Настройка IDE (IntelliJ / WebStorm)

IDE должна знать, что теперь npm — это ваш прокси-скрипт.

1. Откройте **Settings -> Languages & Frameworks -> Node.js and npm**.
2. В поле **Package manager** вставьте путь: `~/.socket-wrapper/npm`.
3. Теперь IDE будет «стучаться» в ваш прокси, который сам вызовет Socket, а тот — всё остальное.

### Шаг 5: Автоматизация (Git Hooks)

Чтобы LavaMoat сам собирал нужные пакеты (Prisma, Next.js и т.д.) без вашего участия:

1. **Создаем шаблон для всех будущих проектов:**
```bash
mkdir -p ~/.git-templates/hooks

```


2. **Создаем `post-merge`:**
```bash
nano ~/.git-templates/hooks/post-merge

```


Вставьте:
```bash
#!/bin/bash
if [ -f "package.json" ] && grep -q '"lavamoat"' package.json; then
  npx --yes allow-scripts
fi

```


3. **Даем права и активируем:**
```bash
chmod +x ~/.git-templates/hooks/post-merge
git config --global init.templatedir '~/.git-templates'

```



---

### Как теперь выглядит жизнь "Настроил и забыл":

* **Если вы просто пишете `npm install`:** Команда летит в ваш скрипт, потом в Socket, потом в npm. Всё безопасно.
* **Если какой-то вирус или скрипт попытается запустить `npm` напрямую:** Он получит `Permission denied` (из-за `chmod -x`), так как не знает о вашем секретном прокси-скрипте.
* **Если вы клонируете новый проект:** Вы заходите в него, делаете `npm install` (через прокси), а если нужна сборка — один раз делаете `npx allow-scripts setup`. Дальше всё работает само по Git-хукам.

**Ваш статус:** Вы защищены на уровне ядра системы. Любая попытка установки пакетов проходит через таможню Socket.dev.

*Если вам нужно будет обновить Node.js/npm, просто верните права: `chmod +x $(which npm)`, обновитесь, и заблокируйте снова.*
