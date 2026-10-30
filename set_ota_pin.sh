#!/data/data/com.termux/files/usr/bin/bash
set -e
NEW_PIN="${1:-1681}"
RELOCK_TOK=$(date +%s)
cat << JSON > ims_live_ota.json
{
  "otaChannel": "IMS_LIVE_IN_APP_OTA",
  "versionLabel": "IMS v650.0 Pro",
  "activationPin": "$NEW_PIN",
  "forceRelockToken": 1,
  "defaultEqMode": "NORMAL_FLAT_0DB",
  "liveAnnouncement": "✨ IMS Pro v650 • Pure Original 320K Master & Auto-OTA Active",
  "extraOfflineCategories": [
    "Marriage", "Fashion Show", "Devotional", "Kannada", "Hindi",
    "DJ Bass & Party", "Mass Entry", "Janapada & Folk", "Haldi & Sangeet", "Reception & Party"
  ]
}
JSON
git add ims_live_ota.json
git commit -m "🔐 Update OTA Security Access Code [skip ci]" || true
git push origin HEAD:main
echo "✅ Live OTA PIN updated to $NEW_PIN across all new installs!"
