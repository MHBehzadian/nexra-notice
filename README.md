# Nexra Panel — Notice Page

A one-page notice for the old Nexra Panel address. It tells users their panel is outdated and gives them two buttons: open the new panel, or contact support.

Every path on the domain serves the same page, so old bookmarks like `/dashboard` and `/dashboard/#/login` all land on it.

## Install

On a fresh Debian/Ubuntu server, with the domain's A record already pointing at it:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/MHBehzadian/nexra-notice/main/install.sh)
```

The defaults are `dash.nexradns.site` on port `8000`. To use a different domain or port, pass them as arguments:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/MHBehzadian/nexra-notice/main/install.sh) dash.nexradns.site 8000
```

The installer sets up nginx and a Let's Encrypt certificate (renewed automatically), then serves the page on the given port and on 443. Run it again to pull the latest version of the page.

## Links

- New panel: https://panel.nexradns.site/dashboard/login
- Support: https://t.me/aria1060

Edit `site/index.html` to change the text or links.
