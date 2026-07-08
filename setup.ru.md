# Zero-Trust npm — Техническая настройка (Fail-Closed)

**Идеология:** безопасный путь должен быть *единственным*. Мы **не** полагаемся на shell-алиасы и настройки IDE — забывчивый юзер или AI-агент просто вызовет `npm` иначе. Enforcement стоит на двух слоях, которые нельзя объехать:

1. **Собственный конфиг npm** (`ignore-scripts`) — читается при любом вызове.
2. **Место бинарника `npm`** — файл по каноническому пути *и есть* wrapper.

> Почему не `chmod -x $(which npm)`? Он не пропускает через таможню — он просто ломает npm, ломает свой же wrapper, слетает при каждом обновлении npm/node и обходится через `node npm-cli.js`. Не используем.

Проверено на macOS (Node из Homebrew) + zsh. Для Linux поправьте пути.

---

## Шаг 1 — Установка сканера Socket

```bash
npm install -g @socketsecurity/cli
socket login
```

`socket npm` / `socket npx` — drop-in обёртки, которые сканируют дерево зависимостей до скачивания пакетов.

> **Границы Free-версии:** известная малварь **блокируется**; то, что ИИ пометил как *потенциальную* угрозу, только **предупреждает**. Поэтому снизу лежит Слой 1 как жёсткий стоп.

---

## Шаг 2 — Слой 1: глобальный локдаун (необходимая таможня исполнения)

```bash
npm config set ignore-scripts true --location=global
```

npm читает этот конфиг **кто бы его ни запускал** — терминал, IDE, агент, subprocess, абсолютный путь. Вредоносные `postinstall`-скрипты (главный вектор supply-chain атак) не выполнятся. Скрипты нужны лишь ~2% пакетов; легитимные вернёт Слой 3.

Проверка:

```bash
npm config get ignore-scripts --location=global   # -> true
```

---

## Шаг 3 — Слой 2: замена бинарника npm на wrapper Socket (fail-closed периметр)

Прячем **настоящие** `npm`/`npx` в приватный, специфичный для версии Node каталог и ставим wrapper на канонический путь. Любой вызов — по имени, по абсолютному пути, из IDE или из агента — попадает в wrapper. Сервисные команды (`run`, `ls`, `--version`, …) идут напрямую в настоящий бинарник; через `socket npm` пускаются только `install`/`i`/`add`/`ci`/`update`/`up`. Логика **идемпотентная** (можно запускать повторно).

Файл wrapper'а — это **sh/Node полиглот**: `@socketsecurity/cli` сам находит «настоящий npm», проверяя файл рядом с запущенным бинарником `node`, и перезапускает его через `node <путь>`, минуя shebang — поэтому wrapper обязан парситься ещё и как валидный JavaScript, иначе этот самовызов падает с `SyntaxError`. Guard через переменную окружения (`__SOCKET_WRAPPER_ACTIVE__`) останавливает бесконечную рекурсию, когда Socket сам вызывает этот же файл обратно.

Это единственная копия этой логики в репозитории — **[`lib/wrap-npm.sh`](lib/wrap-npm.sh)**. `setup-zero-trust.sh` сам скачивает и подключает его при каждом запуске; чтобы применить вручную для текущей активной версии Node:

```bash
curl -fsSL https://raw.githubusercontent.com/hanzhad/npm-zero-trust/main/lib/wrap-npm.sh -o /tmp/wrap-npm.sh
source /tmp/wrap-npm.sh
install_npm_wrapper "$(node -v)" "$HOME/.npm-real/$(node -v)/bin"
```

**Опционально, максимальная жёсткость** — сделать wrapper неудаляемым для юзера/агента:

```bash
sudo chown root:wheel "$(command -v npm)" "$(command -v npx)"
sudo chmod 755        "$(command -v npm)" "$(command -v npx)"
```

Проверка:

```bash
head -5 "$(command -v npm)"        # -> #!/bin/sh  ... socket-wrapper ...
npm install --dry-run left-pad     # должно пройти через Socket
```

---

## Шаг 4 — Закрываем боковые двери

Fail-closed рушится, если агент просто возьмёт другой пакетный менеджер.

Логика лежит в **[`lib/close-side-doors.sh`](lib/close-side-doors.sh)**:

```bash
curl -fsSL https://raw.githubusercontent.com/hanzhad/npm-zero-trust/main/lib/close-side-doors.sh -o /tmp/close-side-doors.sh
source /tmp/close-side-doors.sh
close_side_doors
```

Если установлены `yarn` / `pnpm` / `bun` — оберните их так же, как в Шаге 3 (или удалите).

---

## Шаг 5 — Слой 3: автосборка доверенного (LavaMoat + Git-хук)

Со скриптами выключенными легитимной сборке (Prisma, Next.js, esbuild…) нужен allow-list.

**Один раз на проект:**

```bash
npm i -D @lavamoat/allow-scripts
npx @lavamoat/allow-scripts setup   # пропишет ignore-scripts=true в .npmrc проекта
npx @lavamoat/allow-scripts auto    # соберёт allow-list в package.json (просмотрите его!)
```

**Глобальный хук, чтобы всё запускалось само после `git pull`** — логика лежит в **[`lib/git-hooks.sh`](lib/git-hooks.sh)**:

```bash
curl -fsSL https://raw.githubusercontent.com/hanzhad/npm-zero-trust/main/lib/git-hooks.sh -o /tmp/git-hooks.sh
source /tmp/git-hooks.sh
configure_git_hooks
```

> Шаблон применяется к репозиториям, которые вы `git init` / `git clone` **после** этого. Для существующих — скопируйте хук в `.git/hooks/post-merge`.

---

## Шаг 6 — IDE (подстраховка, уже не критично)

Так как enforcement стоит на бинарнике + конфиге npm, IDE защищена, даже если пропустить этот шаг. Настройка нужна лишь чтобы UI IDE не путался.

* IntelliJ / WebStorm: **Settings → Languages & Frameworks → Node.js and npm → Package manager** → указать на обёрнутый `npm` (его обычный путь подходит — теперь это и есть wrapper).

---

## Как теперь выглядит «Настроил и забыл»

* **`npm install`** → wrapper → скан Socket → настоящий npm, lifecycle-скрипты выключены. Чистые пакеты ставятся, вредоносные блокируются.
* **Агент или забывчивый юзер вызывает `npm` (любым способом)** → всё равно попадает в wrapper; `postinstall` всё равно не выполнится (глобальный `ignore-scripts`). Мимо таможни не пройти.
* **Клонируете проект со сборкой** → один раз `allow-scripts setup`, дальше всё делает Git-хук.

---

## Честно про пределы и эксплуатацию

* **Остаточный обход:** вызов настоящего launcher'а напрямую по его спрятанному пути (`~/.npm-real/<версия-node>/bin/npm`) минует wrapper — а вот канонический путь `npm`/`npx` и `node <этот-путь>` перекрыты оба, потому что wrapper — полиглот, вокруг которого сам Socket объехать не может. Для модели угрозы (забывчивый человек + AI-агент) это приемлемо, но не против целевого злоумышленника, уже исполняющего код локально.
* **`brew upgrade node` вернёт оригинальный npm** и снесёт wrapper. Перезапустите Шаг 3 (он идемпотентный) или повесьте brew post-upgrade хук.
* **Fail-closed = недоступность при сбое.** Нет сети / истёк `socket login` / rate-limit ⇒ установки блокируются — это by design. Break-glass для админа: настоящий бинарник лежит в `~/.npm-real/<версия-node>/bin/npm`.
* **Всегда коммитьте lockfile и используйте `npm ci`** в CI — он ставит строго из lockfile и падает при расхождении.

### Откат

```bash
for v_dir in "$HOME"/.npm-real/*/; do
  v="$(basename "$v_dir")"
  for b in npm npx; do
    bin_path="$HOME/.nvm/versions/node/$v/bin/$b"
    if [ -f "$bin_path" ] && grep -q 'socket-wrapper' "$bin_path" 2>/dev/null; then
      rm -f "$bin_path"
      cp -P "$v_dir/$b" "$bin_path"   # вернуть настоящий launcher
    fi
  done
done
npm config delete ignore-scripts --location=global
git config --global --unset init.templatedir || true
```

---
