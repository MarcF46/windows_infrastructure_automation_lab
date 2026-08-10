# Sicherheitsbaseline

## Ziel

Die Sicherheitsbaseline soll das Lab nicht zu einer vollständigen Enterprise-Sicherheitsplattform machen. Sie zeigt vielmehr, wie typische Windows-Grundmaßnahmen automatisiert, rollenbezogen und anschließend überprüft werden können.

## Windows-Firewall

Für Domain-, Private- und Public-Profil gelten:

```text
Firewall aktiviert
Standard eingehend: Block
Standard ausgehend: Allow
Logging erlaubter Verbindungen: aktiv
Logging blockierter Verbindungen: aktiv
```

Zusätzlich werden nur die für die jeweilige Rolle benötigten eingehenden Verbindungen aus dem Lab-Netz freigegeben.

### DC01

Beispiele für freigegebene Dienste:

- DNS über TCP/UDP 53
- Kerberos über TCP/UDP 88
- LDAP über TCP/UDP 389
- SMB über TCP 445
- RPC Endpoint Mapper über TCP 135
- dynamisches RPC über TCP 49152 bis 65535
- Global Catalog über TCP 3268
- Active Directory Web Services über TCP 9389
- WinRM und RDP für die Verwaltung

### SRV01

Beispiele:

- SMB
- DHCP
- WinRM
- RDP

### CL01

Der Client benötigt im Lab nur begrenzte eingehende Verwaltungszugriffe wie WinRM und RDP.

## Microsoft Defender

Wo die Defender-Cmdlets verfügbar sind, wird geprüft beziehungsweise gesetzt:

- Echtzeitschutz aktiviert
- Skriptscan aktiviert

Die Abschlussprüfung bewertet den tatsächlichen Zustand und nicht nur den Rückgabewert eines Konfigurationsbefehls.

## SMB

Auf den Serverrollen werden folgende Grundmaßnahmen angewendet:

- SMBv1 deaktiviert
- SMB-Signierung erforderlich

Die Freigaben nutzen zusätzlich NTFS- und SMB-Berechtigungen über domänenlokale Ressourcengruppen.

## RDP

Für Remote Desktop wird Network Level Authentication erzwungen. Die Windows-Firewall beschränkt den eingehenden Zugriff zusätzlich auf das interne Lab-Netz.

## LLMNR

LLMNR wird über eine eigene Gruppenrichtlinie deaktiviert. Damit wird eine unnötige lokale Namensauflösungsmethode reduziert, die in modernen Domänenumgebungen häufig nicht benötigt wird.

## Security Event Log

Das maximale Security-Log wird vergrößert, damit im Lab mehr sicherheitsrelevante Ereignisse für Diagnose und Nachvollziehbarkeit verfügbar bleiben.

## Berechtigungen

Das Dateiberechtigungsmodell verwendet AGDLP:

```text
Account -> Global Group -> Domain Local Group -> Permission
```

Dadurch erhalten Benutzer keine direkten ACL-Einträge. Änderungen an Rollen und Ressourcen bleiben getrennt.

## Grenzen

Nicht Bestandteil dieser Baseline sind unter anderem:

- Microsoft Defender for Endpoint
- zentrale SIEM-Anbindung
- PKI und Zertifikatslebenszyklus
- LAPS
- Credential Guard
- AppLocker oder WDAC
- Tiering-Modell für privilegierte Administration
- vollständige CIS- oder Microsoft-Security-Benchmark-Abbildung

Diese Punkte wären sinnvolle spätere Erweiterungen für eine produktionsnähere Umgebung.
