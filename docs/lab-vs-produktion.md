# Lab vs. Produktion

## Einordnung

Das Projekt ist ein Lern- und Portfolio-Lab. Es bildet viele reale Administrationsprinzipien ab, ist aber bewusst kleiner und einfacher als eine produktive Unternehmensumgebung.

## Gegenüberstellung

| Thema | Im Lab | In Produktion zusätzlich sinnvoll |
|---|---|---|
| Virtualisierung | einzelner Hyper-V-Host | Cluster, Hochverfügbarkeit, Kapazitätsplanung |
| Domain Controller | ein DC | mindestens zwei DCs, Standort- und Replikationskonzept |
| DNS | auf DC01 | Redundanz, Monitoring, Forwarder-Konzept |
| DHCP | auf SRV01 | Failover, Reservierungen, IPAM |
| Dateidienste | einzelner Dateiserver | getrenntes Datenvolume, DFS, Quotas, Backup, Restore-Tests |
| Berechtigungen | AGDLP | Rollenmodell, Rezertifizierung, Joiner/Mover/Leaver-Prozess |
| GPO | gezielte Lab-GPOs | Baseline-Konzept, Staging, Freigabe, Versionskontrolle |
| Firewall | rollenbezogene Regeln | zentrale Verwaltung, Segmentierung, Monitoring |
| Defender | lokale Baseline | Defender for Endpoint, zentrale Richtlinien, SOC-Anbindung |
| Logging | lokale Ereignisprotokolle | zentrale Logplattform, SIEM, Retention |
| Secrets | interaktive Eingabe | Secret Vault, Managed Identities, privilegierte Zugriffskonzepte |
| Automatisierung | PowerShell + AutomatedLab | CI/CD, IaC, Tests, Freigaben, Rollback-Pipelines |
| Backup | nicht zentraler Bestandteil | externes Backup, Immutable Copies, regelmäßige Restore-Tests |

## Warum AutomatedLab?

AutomatedLab eignet sich gut für reproduzierbare Schulungs-, Test- und Demonstrationsumgebungen. Es kann Hyper-V-Ressourcen, Betriebssysteme und Windows-Rollen in einem PowerShell-gesteuerten Ablauf verbinden.

Für produktive Serverbereitstellung würden je nach Umgebung eher andere Werkzeuge oder Kombinationen eingesetzt, zum Beispiel:

- PowerShell Desired State Configuration
- Windows Server Management mit zentralen Plattformen
- Ansible
- Terraform für unterstützte Infrastrukturkomponenten
- Packer für Images
- Configuration Manager oder Intune für geeignete Endpunkte
- CI/CD-Pipelines und kontrollierte Deployment-Prozesse

## Was das Lab trotzdem realistisch zeigt

Auch ohne vollständige Enterprise-Komplexität trainiert das Projekt wichtige Arbeitsweisen:

- Abhängigkeiten vor Änderungen prüfen
- Infrastruktur reproduzierbar beschreiben
- Identitäten und Ressourcen getrennt modellieren
- Berechtigungen gruppenbasiert vergeben
- Netzwerk- und Namensdienste gemeinsam betrachten
- Sicherheitsmaßnahmen rollenbezogen anwenden
- Änderungen anschließend technisch verifizieren
- Fehler nicht durch blindes Neuinstallieren überdecken

Diese Prinzipien sind unabhängig von der später eingesetzten Enterprise-Plattform relevant.
