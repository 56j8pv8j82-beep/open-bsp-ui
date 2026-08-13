# Agenda Voz

App nativo para iPhone que transforma comandos de voz em português brasileiro em
compromissos no **Google Agenda**.

> "Me lembra amanhã às 14 horas de ligar para o cliente João."

Toque no microfone, fale, confirme, e o evento é criado no seu calendário.

## Sumário

- [Como funciona](#como-funciona)
- [Requisitos](#requisitos)
- [1. Abrir o projeto no Xcode](#1-abrir-o-projeto-no-xcode)
- [2. Configurar o Bundle Identifier](#2-configurar-o-bundle-identifier)
- [3. Configurar o projeto no Google Cloud](#3-configurar-o-projeto-no-google-cloud)
- [4. Habilitar a Google Calendar API](#4-habilitar-a-google-calendar-api)
- [5. Configurar OAuth 2.0](#5-configurar-oauth-20)
- [6. Cadastrar o iOS Client ID](#6-cadastrar-o-ios-client-id)
- [7. Colocar os identificadores no app](#7-colocar-os-identificadores-no-app)
- [8. Executar no simulador](#8-executar-no-simulador)
- [9. Executar no iPhone físico](#9-executar-no-iphone-físico)
- [10. Testar o Google Calendar](#10-testar-o-google-calendar)
- [Testes](#testes)
- [Arquitetura](#arquitetura)
- [Privacidade](#privacidade)
- [Limitações conhecidas](#limitações-conhecidas)

## Como funciona

1. Você toca no botão de microfone da tela principal.
2. O `SpeechRecognitionService` grava e transcreve com o framework nativo
   `Speech` do iOS (com preferência por reconhecimento on-device).
3. O `LocalCommandInterpreter` interpreta a frase e monta um `ParsedEvent`
   (título, data, hora, duração, local, notas, alerta).
4. Uma tela de confirmação mostra o que foi entendido. Você pode editar antes
   de criar.
5. O `GoogleCalendarService` chama a Google Calendar API v3 para criar o
   evento, usando um token OAuth 2.0 obtido pelo SDK oficial GoogleSignIn.

## Requisitos

| Item                                              | Versão                                                         |
| ------------------------------------------------- | -------------------------------------------------------------- |
| Xcode                                             | 15.3 ou mais recente                                           |
| iOS deployment target                             | 17.0                                                           |
| macOS para desenvolver                            | Sonoma (14) ou mais recente                                    |
| Conta Apple                                       | qualquer (grátis serve para simulador; conta paga para device) |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | 2.38+ (recomendado; opcional)                                  |
| Conta no Google Cloud                             | obrigatório para o Google Calendar funcionar                   |

## 1. Abrir o projeto no Xcode

Este repositório **não** carrega o `.xcodeproj` versionado. Ele é gerado a
partir do `project.yml` pelo [XcodeGen](https://github.com/yonaskolb/XcodeGen).
Isso evita conflitos de merge no `project.pbxproj` e mantém a configuração
declarativa.

Se você ainda não tem o XcodeGen:

```bash
brew install xcodegen
```

Na raiz do projeto (`AgendaVoz/`):

```bash
cd AgendaVoz
xcodegen generate
open AgendaVoz.xcodeproj
```

O Xcode vai resolver o pacote `GoogleSignIn-iOS` automaticamente na primeira
abertura (leva 1-2 minutos).

> **Alternativa sem XcodeGen:** crie um novo projeto SwiftUI no Xcode com
> mesmo bundle ID, arraste as pastas `AgendaVoz/` e `AgendaVozTests/`, e
> adicione o pacote `https://github.com/google/GoogleSignIn-iOS` via **File →
> Add Packages…**. Copie as chaves do `Info.plist` incluso.

## 2. Configurar o Bundle Identifier

O `project.yml` já define `com.example.AgendaVoz` como Bundle ID padrão.
Troque para algo que combine com seu Team ID (`com.seudominio.AgendaVoz`,
por exemplo). Duas formas:

**Via project.yml (recomendado):**

```yaml
targets:
  AgendaVoz:
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.seudominio.AgendaVoz
```

Depois, `xcodegen generate` novamente.

**Direto no Xcode:** selecione o alvo `AgendaVoz` → **Signing & Capabilities**
→ altere o **Bundle Identifier**.

## 3. Configurar o projeto no Google Cloud

1. Acesse [console.cloud.google.com](https://console.cloud.google.com/).
2. Crie um projeto novo (ou use um existente).
3. Anote o **Project ID**.

## 4. Habilitar a Google Calendar API

Dentro do projeto:

1. Menu lateral → **APIs & Services** → **Library**.
2. Busque **Google Calendar API**.
3. Clique em **Enable**.

## 5. Configurar OAuth 2.0

1. **APIs & Services** → **OAuth consent screen**.
2. Escolha **External** (para uso próprio serve; se quiser publicar,
   configure os campos obrigatórios).
3. Preencha nome do app (`Agenda Voz`), e-mail de suporte, e domínio (pode
   deixar em branco no início).
4. Em **Scopes**, adicione:
   - `https://www.googleapis.com/auth/calendar` (leitura e escrita completas).
5. Em **Test users**, adicione seu e-mail (necessário enquanto o app está em
   modo _testing_).

## 6. Cadastrar o iOS Client ID

1. **APIs & Services** → **Credentials** → **Create Credentials** → **OAuth
   client ID**.
2. Tipo: **iOS**.
3. **Bundle ID**: o mesmo do passo 2 (`com.seudominio.AgendaVoz`).
4. Baixe/anote:
   - **Client ID** (algo como `1234567890-abc.apps.googleusercontent.com`).
   - **iOS URL scheme** (o _reversed_ client ID —
     `com.googleusercontent.apps.1234567890-abc`).

## 7. Colocar os identificadores no app

O app lê `GOOGLE_CLIENT_ID` e `GOOGLE_REVERSED_CLIENT_ID` como _build
settings_ — nada de segredos hardcoded em Swift. Duas opções:

### Opção A: `.xcconfig` (recomendada, evita mexer no Xcode)

```bash
cp Config.xcconfig.example Config.xcconfig
# edite com seus valores
```

No Xcode: **Project → Info → Configurations**, associe `Config.xcconfig`
tanto ao Debug quanto ao Release do target `AgendaVoz`.

> `Config.xcconfig` está no `.gitignore` para não vazar credenciais.

### Opção B: Direto nas Build Settings

- Xcode → alvo `AgendaVoz` → **Build Settings** → **User-Defined**.
- Adicione `GOOGLE_CLIENT_ID` e `GOOGLE_REVERSED_CLIENT_ID`.

O `Info.plist` já referencia essas variáveis (`$(GOOGLE_CLIENT_ID)` e
`$(GOOGLE_REVERSED_CLIENT_ID)`) — nada mais precisa ser feito lá.

## 8. Executar no simulador

1. Selecione um simulador (ex.: iPhone 15).
2. **⌘R** para executar.

⚠️ **Reconhecimento de fala no simulador:** o simulador do iOS suporta
`SFSpeechRecognizer`, mas o áudio precisa vir do microfone do Mac. Verifique
**Simulator → Device → Microphone** ativado.

⚠️ **Google Sign-In no simulador:** funciona, mas o Safari embutido pode
demorar. Se travar, feche o simulador e reabra.

## 9. Executar no iPhone físico

1. Conecte o iPhone via cabo (a primeira vez o iPhone pede confiança).
2. No Xcode: **alvo AgendaVoz → Signing & Capabilities → Team**, escolha o
   seu Apple ID.
3. Escolha seu iPhone no seletor de dispositivos.
4. **⌘R**.

Na primeira execução, o iPhone reclama do certificado não confiável. Vá em
**Ajustes → Geral → Gerenciamento de dispositivos e VPN**, autorize seu
perfil de desenvolvedor.

Se aparecer erro de "provisioning", vá em **Xcode → Signing & Capabilities →
Try Again** — ele cria um perfil grátis automaticamente para seu Apple ID.

## 10. Testar o Google Calendar

1. Abra o app.
2. Toque no botão "Conectar Google Agenda".
3. Autorize com sua conta Google (aquela que você cadastrou como _test user_
   no passo 5).
4. Abra as **Configurações** (engrenagem no topo) e escolha um calendário
   padrão.
5. Volte para a tela principal, toque no microfone, fale:

   > "Reunião com Pedro amanhã às 14 horas"

6. Confira o resumo, toque em **Criar**.
7. Abra o Google Agenda no navegador ou no app do iPhone — o evento estará
   lá.

## Testes

Rode a suíte com **⌘U** no Xcode ou pelo terminal:

```bash
xcodebuild test \
  -project AgendaVoz.xcodeproj \
  -scheme AgendaVoz \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

Os testes cobrem todos os cenários exigidos (e mais alguns de robustez):

- "Reunião amanhã às 14 horas"
- "Consulta médica sexta-feira às 9"
- "Ligar para João hoje às 17"
- "Audiência dia 20 de agosto às 13h30"
- "Reunião com cliente daqui a duas horas"
- "Me lembra amanhã de enviar o contrato"
- "Quinta às 15h audiência do processo 5001234"
- "Dia 25 às 10 reunião no escritório"
- "Almoço amanhã ao meio-dia"
- "Daqui a 30 minutos me lembrar do bolo no forno"
- "Reunião depois de amanhã às 10 da manhã"
- frase vazia (verifica erro)

## Arquitetura

```
AgendaVoz/
├── AgendaVozApp.swift          @main + wiring de EnvironmentObjects
├── Views/
│   ├── ContentView.swift        NavigationStack raiz
│   ├── RecordingView.swift      Botão de mic + transcrição em tempo real
│   ├── ConfirmationView.swift   Confirmar/editar antes de criar
│   ├── SettingsView.swift       Conta, calendário, defaults, alertas
│   ├── GoogleSignInView.swift   Fluxo OAuth com GIDSignIn
│   └── CalendarPickerView.swift Escolha do calendário do Google
├── ViewModels/
│   └── RecordingViewModel.swift Estado da tela principal
├── Services/
│   ├── SpeechRecognitionService Speech + AVAudioEngine, on-device
│   ├── GoogleAuthService        Wrapper do SDK GoogleSignIn
│   ├── GoogleCalendarService    Cliente REST v3 (URLSession)
│   └── KeychainService          Wrapper SecItem*
├── Parser/
│   ├── CommandInterpreter.swift        protocolo
│   ├── LocalCommandInterpreter.swift   PT-BR on-device
│   ├── AICommandInterpreter.swift      stub para backend próprio
│   └── PortugueseDateParser.swift      datas/horários pt-BR
├── Models/                     ParsedEvent, GoogleCalendar, Preferences, AppError
├── AppIntents/
│   └── CreateEventIntent.swift Siri Shortcut para criar evento por voz
└── Utilities/                  Haptics, DateFormatting
```

**Padrões:**

- SwiftUI + `@ObservableObject` (Combine) — simples e testável.
- `async/await` em toda camada de I/O.
- `@MainActor` nas classes que tocam UI/UserDefaults.
- Serviços têm inicializador injetável — facilita testes e mocks.

**Preparado para expandir:**

- **IA remota:** `AICommandInterpreter` já está lá; basta apontar
  `backendEndpoint` para _seu_ backend (nunca coloque a chave do LLM no
  cliente iOS — mantenha no servidor).
- **Widget:** criar um Widget Extension e usar o mesmo `LocalCommandInterpreter`.
- **Apple Watch:** um alvo watchOS pode compartilhar `Parser/` e `Models/`.
- **App Intents / Siri:** já implementado (`CreateEventIntent`).

## Privacidade

- Sempre que possível, `SFSpeechRecognitionRequest.requiresOnDeviceRecognition
= true` — o áudio não sai do iPhone.
- Nenhuma senha do Google é armazenada. Só o token OAuth, que o próprio SDK
  do Google guarda no Keychain do dispositivo.
- Nenhuma chave de terceiros embarcada no app.
- Descrições de uso obrigatórias já estão no `Info.plist`
  (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`).

## Limitações conhecidas

- **Parser é heurístico.** Cobre bem os padrões comuns em PT-BR, mas frases
  muito ambíguas caem no fluxo de confirmação/edição em vez de tentar
  adivinhar. Isso é proposital — melhor perguntar do que criar evento
  errado.
- **Fuso horário:** usa o `TimeZone.current` do iPhone. Se você viaja e o
  iPhone mudou de fuso, o app segue o iPhone.
- **Sem widget nem Apple Watch ainda.** Só a estrutura foi preparada.
- **Não usa EventKit** (o calendário local do iPhone) — o objetivo é
  Google Calendar. Isso está declarado no Info.plist como opção futura.
- **Anti-duplicação simples:** olha ±5 minutos com o mesmo título. Se a
  checagem falhar (rede, etc.), o evento é criado mesmo assim (a proteção
  não pode ser mais restritiva que a experiência).
