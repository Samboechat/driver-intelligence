import SwiftUI

/// Primeira abertura: explica e pede todas as permissões, terminando com a transmissão de tela.
struct OnboardingView: View {
    @EnvironmentObject var perms: Permissions
    var done: () -> Void
    @State private var page = 0
    @State private var status = SharedStore.status
    @ObservedObject private var capture = CaptureMonitor.shared
    private var reading: Bool { ReadingState.current(status: status, capture: capture).isOn }
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                notifications.tag(1)
                if printsOn { photos.tag(2) }
                focus.tag(3)
                broadcast.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .background(Palette.background.ignoresSafeArea())
        .onReceive(timer) { _ in
            status = SharedStore.status
            Task { await perms.refresh() }
        }
    }

    /// A página de Fotos só entra com os prints ligados nos Ajustes.
    private var printsOn: Bool { SharedStore.settings.saveScreenshots }

    private func next() { withAnimation { page += (page == 1 && !printsOn) ? 2 : 1 } }

    private var welcome: some View {
        OnboardPage(icon: "bolt.car.fill", color: Palette.brand,
                    title: "Driver Intelligence",
                    text: "Enquanto você usa o Uber Driver, o app lê cada chamado na tela, calcula R$/km, R$/hora e lucro e te avisa por notificação em cerca de 2 segundos se é para aceitar, avaliar ou recusar.\n\nTambém entende se você aceitou ou recusou, mede o tempo real das corridas e acompanha a meta da semana. Nenhuma imagem da tela é guardada.") {
            PrimaryButton("Começar", action: next)
        }
    }

    private var notifications: some View {
        OnboardPage(icon: "bell.badge.fill", color: Palette.warning,
                    title: "Notificações",
                    text: "É por elas que a análise de cada chamado chega por cima do Uber. Toque em Permitir no aviso do iOS.") {
            if perms.notificationsOK {
                Done("Notificações permitidas")
                PrimaryButton("Continuar", action: next)
            } else if perms.notifications == .denied || perms.notificationsQuiet {
                Text(perms.notificationsQuiet
                     ? "As notificações estão em modo silencioso. Abra os Ajustes › Notificações e ative \"Permitir Notificações\", \"Tela Bloqueada\", \"Central\" e \"Faixas\"."
                     : "As notificações foram negadas. Abra os Ajustes › Notificações e ative \"Permitir Notificações\".")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                PrimaryButton("Abrir Ajustes") { perms.openSettings() }
                SecondaryButton("Continuar mesmo assim", action: next)
            } else {
                PrimaryButton("Permitir notificações") { Task { await perms.requestNotifications() } }
            }
        }
    }

    private var photos: some View {
        OnboardPage(icon: "photo.stack.fill", color: Palette.positive,
                    title: "Prints no álbum",
                    text: "Cada chamado que aparecer na tela vira um print no álbum \"Driver Intelligence\" do app Fotos, com a análise salva junto no histórico.\n\nEscolha \"Permitir Acesso Total\" para o app organizar o álbum sozinho.") {
            if perms.photosOK {
                Done("Acesso às Fotos permitido")
                PrimaryButton("Continuar", action: next)
            } else if !PhotoAlbum.notDetermined {
                Text("O acesso às Fotos foi negado. Os prints ficam na aba Prints do app; para mandá-los ao álbum, libere em Ajustes › Driver Intelligence › Fotos.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                PrimaryButton("Abrir Ajustes") { perms.openAppSettings() }
                SecondaryButton("Continuar", action: next)
            } else {
                PrimaryButton("Permitir acesso às Fotos") { Task { await perms.requestPhotos() } }
            }
        }
    }

    private var focus: some View {
        OnboardPage(icon: "moon.fill", color: Color.purple,
                    title: "Foco e Condução",
                    text: "Se você dirige com o Foco \"Condução\" ou \"Não Perturbe\", inclua o Driver Intelligence nos apps permitidos:\n\nAjustes › Foco › Condução › Apps › Adicionar › Driver Intelligence.\n\nSem isso, as análises ficam escondidas enquanto você dirige.") {
            PrimaryButton("Já fiz / não uso Foco") {
                UserDefaults.standard.set(true, forKey: "focusConfirmed")
                next()
            }
        }
    }

    private var broadcast: some View {
        OnboardPage(icon: "record.circle", color: Palette.negative,
                    title: "Compartilhar a tela",
                    text: "Último passo: toque abaixo, escolha \"Driver Intelligence\" e \"Iniciar Transmissão\". O iOS pede essa confirmação toda vez que a leitura é ligada.\n\nTudo é processado no próprio iPhone; nada é enviado para a internet.") {
            BroadcastButton(running: reading)
            if reading {
                Done("Transmissão ativa")
                PrimaryButton("Concluir", action: done)
            } else {
                Text("Se a janela não abrir: Central de Controle › segure o botão de Gravação de Tela › Driver Intelligence › Iniciar Transmissão.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                SecondaryButton("Fazer depois", action: done)
            }
        }
    }
}

private struct OnboardPage<Actions: View>: View {
    var icon: String
    var color: Color
    var title: String
    var text: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle().fill(color.opacity(0.16)).frame(width: 120, height: 120)
                Image(systemName: icon).font(.system(size: 50, weight: .semibold)).foregroundStyle(color)
            }
            Text(title).font(.title.bold()).multilineTextAlignment(.center)
            Text(text).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: 10) { actions }
            Spacer().frame(height: 50)
        }
        .padding(.horizontal, 24)
    }
}

private struct Done: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.positive)
    }
}

struct PrimaryButton: View {
    var title: String
    var action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(Palette.background)
                .background(Palette.brand, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct SecondaryButton: View {
    var title: String
    var action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(title, action: action).font(.subheadline.weight(.semibold)).padding(.vertical, 8)
    }
}
