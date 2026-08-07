#!/usr/bin/env python3
# Generate the 26 ProStaff translation files. English is authoritative; every
# other language ships an [EN] placeholder (localize when available), matching
# the DairyCore pattern. Keys mirror the strings baked into the Lua.
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "translations"))

# 26 FS25 languages (fc = Simplified Chinese; no separate cs for a new mod).
LANGS = ["en", "de", "fr", "nl", "it", "pl", "es", "ea", "pt", "br", "ru", "uk",
         "cz", "hu", "ro", "tr", "fi", "no", "sv", "da", "kr", "jp", "ct", "fc",
         "id", "vi"]

# name -> English text
ENTRIES = [
    ("ps_setting_enabled",         "Pro Staff Co-Op Enabled"),
    ("ps_setting_baseCost",        "Level Base Cost"),
    ("ps_setting_subscriptionFee", "Agronomy Report Sub Fee"),
    ("ps_setting_agronomyFee",     "Agronomy Fee (per month)"),
    ("ps_tab_title",               "Pro Staff"),
    # 20 Co-Op level names (mirror ProStaffConstants.LEVEL_NAMES)
    ("ps_level_1",  "Office Access"),
    ("ps_level_2",  "Procurement Access"),
    ("ps_level_3",  "Scheduling Optimization"),
    ("ps_level_4",  "Comms Relay"),
    ("ps_level_5",  "Labor Welfare"),
    ("ps_level_6",  "Loading Automation"),
    ("ps_level_7",  "Bulk Silo Admin"),
    ("ps_level_8",  "Regional Mesh"),
    ("ps_level_9",  "Personnel Records"),
    ("ps_level_10", "Academic Liaison"),
    ("ps_level_11", "Labor Recovery"),
    ("ps_level_12", "Precision Agronomy"),
    ("ps_level_13", "Global Comms"),
    ("ps_level_14", "Fleet Logistics"),
    ("ps_level_15", "Syndicate Board"),
    ("ps_level_16", "Curriculum Admin"),
    ("ps_level_17", "Payroll Oversight"),
    ("ps_level_18", "Predictive Control"),
    ("ps_level_19", "System Overdrive"),
    ("ps_level_20", "Sovereign Admin"),
    # Audit line labels (mirror ProStaffConstants.LABELS + AGRONOMY_FEE.LABEL)
    ("ps_label_investment",     "Co-Op Membership Investment"),
    ("ps_label_agronomyFee",    "Co-Op Agronomy Report Sub"),
    ("ps_label_herdsmanRebate", "Co-Op Personnel Rebate"),
    ("ps_label_fleetRebate",    "Co-Op Fleet Rebate"),
]


def xml_escape(s):
    return (s.replace("&", "&amp;").replace('"', "&quot;")
             .replace("<", "&lt;").replace(">", "&gt;"))


def build(lang):
    lines = ['<?xml version="1.0" encoding="utf-8" standalone="no" ?>']
    if lang != "en":
        lines.append("<!-- [EN] placeholder translations; localize when available -->")
    lines.append("<l10n>")
    lines.append("    <texts>")
    for name, text in ENTRIES:
        lines.append('        <text name="%s" text="%s" />' % (name, xml_escape(text)))
    lines.append("    </texts>")
    lines.append("</l10n>")
    return "\n".join(lines) + "\n"


def main():
    os.makedirs(OUT, exist_ok=True)
    for lang in LANGS:
        path = os.path.join(OUT, "translation_%s.xml" % lang)
        with open(path, "w", encoding="utf-8") as f:
            f.write(build(lang))
    print("Wrote %d translation files to %s" % (len(LANGS), OUT))


if __name__ == "__main__":
    main()
