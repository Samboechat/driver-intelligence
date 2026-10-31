# Instalação e compilação

## Requisitos

- JDK 17 (o Android Studio já traz um)
- Android SDK com plataforma 35 (o Gradle baixa sozinho se as licenças estiverem aceitas)
- Celular Android 10+ para testar a leitura sobre o Uber Driver

## Opção A — GitHub Actions (recomendado, sem configurar nada)

1. Crie um repositório (pode ser privado) e envie a pasta do projeto.
2. A cada push na `main`, o workflow **Android CI** roda os testes e gera:
   - `app-debug.apk` — para instalar e testar
   - `app-release-unsigned.apk` / `.aab` — ou assinados, se você configurar a keystore
3. Baixe em *Actions → execução → Artifacts → driver-intelligence-apks*.
4. Relatórios de teste em *Artifacts → test-reports*.

Testes instrumentados (OCR sintético no emulador): *Actions → Android CI → Run workflow → marcar "instrumented"*.

### Assinatura de release (opcional)

Gere uma keystore uma vez:

```bash
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias driverintelligence
base64 -w0 release.jks   # copie a saída
```

Cadastre em *Settings → Secrets and variables → Actions*: `DI_KEYSTORE_BASE64`, `DI_KEYSTORE_PASSWORD`, `DI_KEY_ALIAS`, `DI_KEY_PASSWORD`. **Nunca** versione a keystore.

## Opção B — Android Studio

1. *File → Open* → pasta `DriverIntelligence`.
2. Aguarde o *Gradle Sync*.
3. *Build → Build App Bundle(s)/APK(s) → Build APK(s)*.

Terminal:

```bash
./gradlew testDebugUnitTest    # testes unitários (inclui Robolectric)
./gradlew assembleDebug        # APK em app/build/outputs/apk/debug/
./gradlew connectedDebugAndroidTest   # com aparelho/emulador conectado
```

## Instalar no celular

1. Copie `app-debug.apk` para o celular (ou `adb install app-debug.apk`).
2. Permita "instalar apps desconhecidos" para o gerenciador de arquivos, quando pedido.
3. Abra o **Driver Intelligence**, siga as permissões e cadastre o veículo.
4. Toque em **Iniciar assistente**, autorize a captura (tela inteira) e abra o Uber Driver.

O APK debug usa o id `com.driverintelligence.app.debug`, então pode conviver com uma versão release.

## Primeiro teste recomendado

1. **Laboratório de OCR** (Ajustes → Diagnóstico): selecione prints reais de ofertas. Confira se valor, distâncias e tempos foram lidos e a confiança.
2. **Análise manual**: digite uma oferta conhecida e confira o cálculo.
3. **Assistente**: com o Uber Driver online, observe o overlay. Se a leitura falhar, gere prints e ajuste o parser com eles como novos casos de teste em `OfferTextParserTest`.

## Atualizar dependências

As versões estão em `gradle/libs.versions.toml`. Para subir de patamar (ex.: Kotlin 2.1+, AGP 8.10+, compileSdk/targetSdk 36), atualize em conjunto Kotlin, KSP (mesmo prefixo da versão do Kotlin), AGP e Compose BOM, e rode os testes.

## Se o primeiro build falhar

O núcleo foi testado; a camada Android foi escrita sem acesso ao SDK. Se aparecer erro de compilação, ele indicará arquivo e linha — normalmente import ou assinatura de API. Corrija e rode `./gradlew assembleDebug` de novo.
