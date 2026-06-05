# 🐋 Running Orca IDE on Your Android Tablet (with SD Card)

> **Reality check:** Orca is an Electron desktop app — it can't be installed as an APK directly.
> But with **Termux + SD card storage + a Linux environment**, you can get a fully working
> Orca dev setup running on your tablet. This guide walks you through every step.

---

## 📋 What You'll Need

| Item | Details |
|---|---|
| Android tablet | Android 9+ recommended |
| SD card | 32GB minimum, 64GB+ recommended |
| Internet connection | For downloading packages |
| A keyboard | Strongly recommended for coding |

---

## 🗂️ Step 1 — Set Up Your SD Card

1. Insert your SD card into your tablet.
2. Go to **Settings → Storage → SD Card**.
3. Format it as **Portable Storage** (NOT internal) — this keeps it accessible and writable.
4. Note the SD card path — it will usually be:
   ```
   /storage/XXXX-XXXX/
   ```
   (You'll see the exact label in your file manager.)

---

## 📦 Step 2 — Install Termux

Termux is a full Linux terminal emulator for Android. **Do NOT install from the Play Store** — that version is outdated.

1. Open your tablet browser and go to:
   ```
   https://github.com/termux/termux-app/releases
   ```
2. Download the latest **termux-app_v*.*.*.apk** (arm64-v8a for most modern tablets).
3. Before installing, enable sideloading:
   - **Settings → Apps → Special App Access → Install Unknown Apps**
   - Allow your browser or file manager.
4. Tap the downloaded APK and install it.

---

## ⚙️ Step 3 — Configure Termux to Use Your SD Card

Open Termux and run these commands one at a time:

```bash
# Update package lists
pkg update && pkg upgrade -y

# Grant Termux access to your storage (including SD card)
termux-setup-storage
```

- A permission popup will appear — tap **Allow**.
- Your SD card will now be accessible at:
  ```
  ~/storage/external-1/
  ```

Set your working directory on the SD card:

```bash
cd ~/storage/external-1
mkdir orca-workspace
cd orca-workspace
```

---

## 🛠️ Step 4 — Install Required Software in Termux

Run each block in order:

### Install core tools
```bash
pkg install -y git nodejs-lts python make
```

### Install pnpm (Orca's package manager)
```bash
npm install -g pnpm
```

### Verify installs
```bash
node --version    # should show v20+
pnpm --version    # should show 8+
git --version
```

---

## 📥 Step 5 — Clone Orca from GitHub

```bash
cd ~/storage/external-1/orca-workspace

git clone https://github.com/stablyai/orca.git
cd orca
```

---

## 📦 Step 6 — Install Orca's Dependencies

```bash
pnpm install
```

This will download all required packages. It may take **5–15 minutes** depending on your internet speed. Files will be saved to your SD card.

---

## 🚀 Step 7 — Run Orca in Dev Mode

> **Note:** Orca's full Electron GUI cannot run on Android. What you CAN run is
> the **Vite dev server** (the web frontend), which you access in your tablet's browser.

```bash
pnpm dev
```

Once it starts, you'll see a local URL like:

```
http://localhost:5173
```

Open your tablet's browser and navigate to that address. You'll see Orca's UI running locally.

---

## 🔄 Step 8 — Keeping Orca Updated

Whenever you want the latest version:

```bash
cd ~/storage/external-1/orca-workspace/orca

# Pull latest changes from GitHub
git pull

# Reinstall any new dependencies
pnpm install

# Start it back up
pnpm dev
```

---

## 💡 Tips for a Better Experience

### Keep Termux Running in the Background
- Android may kill Termux. To prevent this:
  - Go to **Settings → Battery → Orca / Termux → No restrictions**
  - Or use the **Termux:Boot** add-on (also on GitHub releases) to auto-start.

### Use a Split Screen
- Run Termux on one side, your browser on the other for a true IDE feel.

### Add a Physical Keyboard
- A Bluetooth keyboard makes coding in Termux dramatically easier.

### Install a Better File Manager
- **Material Files** (free, on Play Store) can browse your SD card and Termux files easily.

---

## ⚠️ Known Limitations

| Limitation | Why |
|---|---|
| No native APK | Orca is Electron-based, not Android-native |
| No full GUI | Electron's window system doesn't run on Android |
| Some features may not work | Terminal emulation in Termux differs from desktop Linux |
| AI agents (Claude Code, Codex) | These require their own API keys and CLI installs — see each agent's own setup docs |

---

## 🤖 Optional: Install Claude Code (AI Agent)

If you want to run AI coding agents inside Orca:

```bash
# Install Claude Code CLI
npm install -g @anthropic-ai/claude-code

# You'll need an Anthropic API key from:
# https://console.anthropic.com
```

---

## 📁 Your SD Card File Structure (When Done)

```
SD Card (external-1/)
└── orca-workspace/
    └── orca/
        ├── src/
        ├── build/
        ├── node_modules/
        ├── package.json
        └── ...
```

---

*Guide based on stablyai/orca (MIT License) — https://github.com/stablyai/orca*
*Last updated: June 2026*
