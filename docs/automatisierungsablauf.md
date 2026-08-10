# Automatisierungsablauf

## Grundidee

Das Lab ist in bewusst getrennte Schritte aufgeteilt. Dadurch lässt sich jeder Abschnitt einzeln prüfen, wiederholen und dokumentieren. Ein Fehler in einem späteren Schritt erfordert nicht automatisch eine vollständige Neuinstallation der Umgebung.

## 1. Voraussetzungen prüfen

`scripts/01-Test-LabPrerequisites.ps1`

Geprüft werden unter anderem:

- administrative PowerShell-Sitzung
- PowerShell 7
- Hyper-V und VMMS
- AutomatedLab
- registrierter LabSources-Pfad
- Windows-Installationsmedien
- freier Speicherplatz
- verfügbarer Arbeitsspeicher

Dieser Schritt ist ausschließlich lesend.

## 2. Virtuelle Infrastruktur bereitstellen

`scripts/02-Deploy-WindowsInfrastructureLab.ps1`

Der Bereitstellungsschritt definiert:

- internen Hyper-V-Switch
- Active-Directory-Domäne
- DC01
- SRV01
- CL01
- VM-Ressourcen
- Secure Boot
- virtuelles TPM für den Windows-11-Client

Vor der Erstellung werden Namens- und Ressourcenkollisionen geprüft. Das Administratorkennwort wird interaktiv abgefragt und nicht im Repository hinterlegt.

## 3. Active Directory strukturieren

`scripts/03-Initialize-ActiveDirectory.ps1`

Erstellt werden:

- verwaltete OU-Hierarchie
- Benutzer-, Computer-, Server- und Gruppenbereiche
- globale Rollengruppen
- domänenlokale Ressourcengruppen
- AGDLP-Verschachtelung
- neutrale Beispielbenutzer

Die Objektanlage ist auf wiederholbare Ausführung ausgelegt. Bereits vorhandene Objekte werden nicht blind dupliziert.

## 4. Dateiserver konfigurieren

`scripts/04-Configure-FileServer.ps1`

Vor Änderungen auf SRV01 wird zuerst das Gruppenmodell auf DC01 geprüft. Anschließend werden:

- Datenordner angelegt
- NTFS-DACLs definiert
- SMB-Freigaben erstellt
- domänenlokale Ressourcengruppen berechtigt
- Access-Based Enumeration aktiviert

Damit bleibt die Berechtigung an Ressourcen von der Benutzerzuordnung getrennt.

## 5. Netzwerkdienste konfigurieren

`scripts/05-Configure-NetworkServices.ps1`

Der Host erhält die interne Gateway-Adresse und eine NAT-Konfiguration. SRV01 wird anschließend als DHCP-Server eingerichtet.

Der DHCP-Bereich verteilt:

- IPv4-Adressen
- internes Gateway
- DC01 als DNS-Server
- die Lab-DNS-Domäne

## 6. Netzlaufwerke per GPO bereitstellen

`scripts/06-Configure-DriveMappingGpo.ps1`

Das Skript erzeugt eine eigene Gruppenrichtlinie und hinterlegt Group Policy Preferences Drive Maps in SYSVOL.

Die Zuordnung erfolgt über Item-Level Targeting:

```text
G:  General      -> GG_All_Employees
F:  Finance      -> GG_Finance_Employees
H:  HR           -> GG_HR_Employees
I:  IT           -> GG_IT_Employees
O:  Operations   -> GG_Operations_Employees
S:  Sales        -> GG_Sales_Employees
```

Die Netzlaufwerke verbessern die Benutzbarkeit. Die eigentliche Sicherheitsgrenze bleiben jedoch SMB- und NTFS-Berechtigungen.

## 7. Sicherheitsbaseline anwenden

`scripts/07-Apply-SecurityBaseline.ps1`

Die Baseline umfasst unter anderem:

- aktivierte Windows-Firewall
- eingehendes Blockieren als Standard
- rollenbezogene Freigaben nur aus dem Lab-Netz
- Firewall-Logging
- Microsoft Defender
- deaktiviertes SMBv1
- erforderliche SMB-Signierung auf Servern
- RDP mit Network Level Authentication
- deaktiviertes LLMNR
- größeres Security Event Log

## 8. Endzustand prüfen

`scripts/08-Test-LabState.ps1`

Die Abschlussprüfung ist lesend und kontrolliert zentrale Sollzustände:

- alle drei VMs vorhanden und gestartet
- erwartete Active-Directory-Domäne
- OU- und Gruppenstruktur
- SMB-Freigaben
- aktiver DHCP-Bereich
- SMBv1 deaktiviert
- SMB-Signierung aktiviert
- Windows-Firewall aktiv
- Defender-Echtzeitschutz

Ein Lab-Schritt gilt damit nicht allein deshalb als erfolgreich, weil ein Änderungsbefehl ohne Fehler beendet wurde. Der gewünschte Endzustand wird anschließend separat geprüft.
