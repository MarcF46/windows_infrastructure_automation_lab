# Windows Infrastructure Automation Lab

Praxisnahes Portfolio-Projekt zur automatisierten Bereitstellung und Konfiguration einer kleinen Windows-Infrastruktur mit **Hyper-V, AutomatedLab, Active Directory und PowerShell**.

Das Lab bildet eine typische kleine Unternehmensumgebung mit Domain Controller, Datei-/DHCP-Server und Windows-Client ab. Im Mittelpunkt stehen reproduzierbare Bereitstellung, strukturierte Rechtevergabe, Gruppenrichtlinien, Netzwerkdienste, Sicherheitsmaßnahmen und überprüfbare Endzustände.

## Projektüberblick

Das Projekt verbindet klassische Systemintegration mit Automatisierung. Eine Umgebung aus drei virtuellen Maschinen wird geplant, bereitgestellt, konfiguriert und anschließend technisch geprüft.

Dabei geht es nicht nur darum, virtuelle Maschinen zu starten. Die einzelnen Schritte bilden einen vollständigen administrativen Ablauf ab:

1. Voraussetzungen und Installationsmedien prüfen
2. Hyper-V- und AutomatedLab-Umgebung definieren
3. Domain Controller, Mitgliedsserver und Client bereitstellen
4. Active Directory strukturieren
5. AGDLP-Gruppenmodell aufbauen
6. Datei- und Netzwerkdienste konfigurieren
7. Netzlaufwerke per Gruppenrichtlinie zuweisen
8. Windows-Sicherheitsbaseline anwenden
9. Endzustände automatisiert verifizieren

## Architektur

```mermaid
flowchart TB
    Internet((Internet))
    Host[Hyper-V Host<br/>Windows 11 Pro]
    Switch[Interner Hyper-V-Switch<br/>WindowsInfraLab]
    DC[DC01<br/>Windows Server 2022<br/>AD DS + DNS]
    SRV[SRV01<br/>Windows Server 2022<br/>Dateiserver + DHCP]
    CL[CL01<br/>Windows 11 Enterprise<br/>Domänenclient]

    Internet -->|NAT über Host| Host
    Host --> Switch
    Switch --> DC
    Switch --> SRV
    Switch --> CL

    DC -. corp.example .- SRV
    DC -. corp.example .- CL
```

### Beispieladressierung

| System | Adresse | Aufgabe |
|---|---|---|
| Hyper-V-Host | `192.168.50.1` | NAT-Gateway und Verwaltung |
| DC01 | `192.168.50.10` | Active Directory und DNS |
| SRV01 | `192.168.50.20` | Dateiserver und DHCP |
| CL01 | `192.168.50.30` | Windows-Domänenclient |

Beispieldomäne: `corp.example`

## Was wurde umgesetzt?

### Hyper-V und AutomatedLab

- reproduzierbare Drei-VM-Topologie
- interner Hyper-V-Switch
- Windows Server 2022 und Windows 11 als Lab-Systeme
- Dynamic Memory und Generation-2-VMs
- Secure Boot und virtuelles TPM für den Client
- Kollisions- und Ressourcenprüfungen vor der Bereitstellung

### Active Directory

- strukturierte OU-Hierarchie
- getrennte Bereiche für Benutzer, Computer, Server, Gruppen und privilegierte Konten
- globale Rollen- und domänenlokale Ressourcengruppen
- Beispielbenutzer für mehrere Unternehmensbereiche
- kontrollierte Computerobjekt-Platzierung

### AGDLP und Dateidienste

Das Rechtekonzept folgt dem klassischen AGDLP-Prinzip:

```text
Benutzer
  -> globale Rollengruppe
  -> domänenlokale Ressourcengruppe
  -> NTFS- und SMB-Berechtigung
```

Für allgemeine Daten und mehrere Fachbereiche werden getrennte SMB-Freigaben mit passenden NTFS-Rechten angelegt.

### Gruppenrichtlinien

- eigene GPO für Netzlaufwerke
- Group Policy Preferences Drive Maps
- Item-Level Targeting über globale Sicherheitsgruppen
- allgemeines Laufwerk plus bereichsbezogene Laufwerke
- GPO-Verknüpfung an die verwaltete Benutzer-OU

### Netzwerkdienste

- internes IPv4-Netz
- NAT über den Hyper-V-Host
- DNS über DC01
- DHCP auf SRV01
- definierter DHCP-Adressbereich und DNS-/Gateway-Optionen

### Sicherheitsbaseline

- Windows-Firewall auf allen Profilen aktiviert
- eingehende Standardaktion `Block`
- ausgehende Standardaktion `Allow`
- rollenbezogene Firewallregeln
- Firewall-Logging für erlaubte und blockierte Verbindungen
- Microsoft Defender und Echtzeitschutz
- SMBv1 deaktiviert
- SMB-Signierung auf Servern erforderlich
- Network Level Authentication für RDP
- LLMNR über Gruppenrichtlinie deaktiviert
- vergrößertes Security Event Log

## Projektstruktur

```text
.
├── config/
│   └── lab.example.psd1
├── docs/
│   ├── architektur.md
│   ├── automatisierungsablauf.md
│   ├── lab-vs-produktion.md
│   └── sicherheitsbaseline.md
├── logs/
│   └── .gitkeep
├── reports/
│   └── .gitkeep
├── scripts/
│   ├── 01-Test-LabPrerequisites.ps1
│   ├── 02-Deploy-WindowsInfrastructureLab.ps1
│   ├── 03-Initialize-ActiveDirectory.ps1
│   ├── 04-Configure-FileServer.ps1
│   ├── 05-Configure-NetworkServices.ps1
│   ├── 06-Configure-DriveMappingGpo.ps1
│   ├── 07-Apply-SecurityBaseline.ps1
│   └── 08-Test-LabState.ps1
├── .gitignore
└── README.md
```

## Typischer Ablauf

Zuerst wird die Beispielkonfiguration lokal kopiert:

```powershell
Copy-Item .\config\lab.example.psd1 .\config\lab.psd1
```

Danach werden lokale ISO-Pfade und gegebenenfalls Ressourcenwerte in `config/lab.psd1` angepasst. Diese Datei wird durch `.gitignore` nicht veröffentlicht.

Die Automatisierung kann anschließend schrittweise ausgeführt werden:

```powershell
.\scripts\01-Test-LabPrerequisites.ps1
.\scripts\02-Deploy-WindowsInfrastructureLab.ps1
.\scripts\03-Initialize-ActiveDirectory.ps1
.\scripts\04-Configure-FileServer.ps1
.\scripts\05-Configure-NetworkServices.ps1
.\scripts\06-Configure-DriveMappingGpo.ps1
.\scripts\07-Apply-SecurityBaseline.ps1
.\scripts\08-Test-LabState.ps1
```

Kennwörter werden nicht im Repository hinterlegt. Wo Zugangsdaten für die Lab-Bereitstellung oder Beispielbenutzer benötigt werden, erfolgt die Eingabe interaktiv.

## Technische Schwerpunkte

Das Projekt zeigt insbesondere:

- Infrastruktur als wiederholbaren Ablauf statt manueller Einzelkonfiguration
- PowerShell-Automatisierung über Host und virtuelle Windows-Systeme hinweg
- Active-Directory-Design und Gruppenmodellierung
- AGDLP als nachvollziehbares Berechtigungskonzept
- Zusammenspiel von DNS, DHCP, NAT und Domänenmitgliedschaft
- Gruppenrichtlinien und Group Policy Preferences
- rollenbezogene Windows-Firewall-Konfiguration
- Sicherheitsmaßnahmen mit anschließender Verifikation
- idempotente beziehungsweise kollisionsbewusste Skriptlogik

## Öffentliche Portfolio-Fassung

Dieses Repository ist eine für die öffentliche Präsentation kuratierte Fassung eines umfangreicheren Arbeits-Labs. Historische Debug-, Reparatur- und Zwischenstandsskripte wurden bewusst nicht übernommen. Die öffentliche Struktur konzentriert sich auf die wesentlichen technischen Schritte und verwendet ausschließlich neutrale Beispielwerte.

Die Skripte basieren auf den praktisch durchgeführten Lab-Schritten. Da Hyper-V-, ISO- und AutomatedLab-Zustände vom jeweiligen Host abhängen, sollten vor einer erneuten Ausführung immer die Voraussetzungen und die lokale Konfiguration geprüft werden.

## Lab und produktiver Betrieb

Das Projekt demonstriert wichtige Windows-Administrations- und Automatisierungsprinzipien, ersetzt aber keine vollständige Enterprise-Plattform.

Für einen produktiven Einsatz wären unter anderem zusätzliche Themen relevant:

- getrennte Tiering- und Administrationsmodelle
- zentrale Secret-Verwaltung
- Patch- und Update-Management
- Backup mit externen Restore-Tests
- zentrale Protokollierung und SIEM
- Monitoring und Alerting
- PKI und Zertifikatsmanagement
- hochverfügbare Domänendienste
- Change-, Freigabe- und Rollback-Prozesse
- Infrastructure-as-Code- und CI/CD-Integration

Mehr dazu: [Lab vs. Produktion](docs/lab-vs-produktion.md)

## Dokumentation

- [Architektur](docs/architektur.md)
- [Automatisierungsablauf](docs/automatisierungsablauf.md)
- [Sicherheitsbaseline](docs/sicherheitsbaseline.md)
- [Lab vs. Produktion](docs/lab-vs-produktion.md)

## Portfolio-Hinweis

Das Projekt wurde als praktischer Nachweis für Windows-Systemadministration, Systemintegration und Automatisierung aufgebaut. Der Schwerpunkt liegt auf verständlicher Struktur, reproduzierbaren Abläufen und überprüfbaren Ergebnissen statt auf einer möglichst großen Anzahl einzelner Skripte.
