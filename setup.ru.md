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

Прячем **настоящие** `npm`/`npx` в приватный каталог и ставим wrapper на канонический путь. Любой вызов — по имени, по абсолютному пути, из IDE или из агента — попадает в wrapper. Скрипт **идемпотентный** (можно запускать повторно).

```bash
#!/usr/bin/env bash
set -euo pipefail

REAL_DIR="$HOME/.npm-real/bin"
mkdir -p "$REAL_DIR"

# переносимый резолвер симлинков (у macOS readlink нет -f)
resolve() {
  f="$1"
  while [ -L "$f" ]; do
    l="$(readlink "$f")"
    case "$l" in /*) f="$l" ;; *) f="$(cd "$(dirname "$f")" && pwd)/$l" ;; esac
  done
  printf '%s\n' "$f"
}

for b in npm npx; do
  bin_path="$(command -v "$b" || true)"
  [ -n "$bin_path" ] || { echo "пропуск: $b не найден"; continue; }
  bin_dir="$(dirname "$bin_path")"

  # 1) прячем НАСТОЯЩИЙ бинарник (только если ещё не обёрнут)
  if ! grep -q 'socket-wrapper' "$bin_path" 2>/dev/null; then
    ln -sf "$(resolve "$bin_path")" "$REAL_DIR/$b"   # абсолютная ссылка на реальный launcher
    rm -f "$bin_path"
  fi

  # 2) ставим wrapper на канонический путь
  cat > "$bin_dir/$b" <<EOF
#!/bin/sh
# socket-wrapper: fail-closed периметр для $b
# Настоящий npm первым в PATH, чтобы 'socket' нашёл его (и не было рекурсии в нас же).
#
# Smart routing: через 'socket' пускаем только команды, модифицирующие пакеты.
# Сервисные/диагностические команды (doctor, --version, ls, run и т.п.) идут
# напрямую в настоящий бинарник — 'socket' не умеет обрабатывать такие вызовы
# в неинтерактивной среде (IDE, AI-агент), зависает и течёт по памяти из-за
# нескончаемого буфера stdout.
CMD="\$1"
case "\$CMD" in
  install|i|add|ci|update|up)
    exec env PATH="\$HOME/.npm-real/bin:\$PATH" socket $b "\$@"
    ;;
  *)
    exec env PATH="\$HOME/.npm-real/bin:\$PATH" "\$HOME/.npm-real/bin/$b" "\$@"
    ;;
esac
EOF
  chmod +x "$bin_dir/$b"
  echo "обёрнут: $bin_dir/$b  (настоящий -> $REAL_DIR/$b)"
done
```

**Опционально, максимальная жёсткость** — сделать wrapper неудаляемым для юзера/агента:

```bash
sudo chown root:wheel "$(command -v npm)" "$(command -v npx)"
sudo chmod 755        "$(command -v npm)" "$(command -v npx)"
```

Проверка:

```bash
head -3 "$(command -v npm)"        # -> #!/bin/sh  ... socket-wrapper ...
npm install --dry-run left-pad     # должно пройти через Socket
```

---

## Шаг 4 — Закрываем боковые двери

Fail-closed рушится, если агент просто возьмёт другой пакетный менеджер.

```bash
# yarn (глобально):
echo "enableScripts: false" >> ~/.yarnrc.yml
# pnpm:
pnpm config set ignore-scripts true --global 2>/dev/null || true
# запретить corepack поднимать «чистый» yarn/pnpm:
corepack disable 2>/dev/null || true
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

**Глобальный хук, чтобы всё запускалось само после `git pull`:**

```bash
mkdir -p ~/.git-templates/hooks
cat > ~/.git-templates/hooks/post-merge <<'EOF'
#!/bin/sh
# запускаем allow-scripts только для проектов, где он подключён
if [ -f package.json ] && grep -q '"lavamoat"' package.json; then
  npx --yes @lavamoat/allow-scripts
fi
EOF
chmod +x ~/.git-templates/hooks/post-merge
git config --global init.templatedir '~/.git-templates'
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

* **Остаточный обход:** `node /путь/к/npm-cli.js` минует wrapper. Для модели угрозы (забывчивый человек + AI-агент) это приемлемо, но не против целевого злоумышленника, уже исполняющего код локально.
* **`brew upgrade node` вернёт оригинальный npm** и снесёт wrapper. Перезапустите Шаг 3 (он идемпотентный) или повесьте brew post-upgrade хук.
* **Fail-closed = недоступность при сбое.** Нет сети / истёк `socket login` / rate-limit ⇒ установки блокируются — это by design. Break-glass для админа: настоящий бинарник лежит в `~/.npm-real/bin/npm`.
* **Всегда коммитьте lockfile и используйте `npm ci`** в CI — он ставит строго из lockfile и падает при расхождении.

### Откат

```bash
for b in npm npx; do
  bin_path="$(command -v "$b")"; bin_dir="$(dirname "$bin_path")"
  if grep -q 'socket-wrapper' "$bin_path" 2>/dev/null; then
    rm -f "$bin_path"
    cp -P "$HOME/.npm-real/bin/$b" "$bin_dir/$b"   # вернуть настоящий launcher
  fi
done
npm config delete ignore-scripts --location=global
git config --global --unset init.templatedir || true
```

---
