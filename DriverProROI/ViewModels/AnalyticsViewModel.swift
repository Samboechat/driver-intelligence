import Foundation

/// Indicadores derivados para a aba Análises.
struct AnalyticsViewModel {
    let rangeDays: Int
    let since: Date
    let totals: PeriodTotals
    let categories: [CategoryPerformance]
    let profile: [ProfileBucket]
    let cpk: CostPerKm
    let audit: OdometerAudit
    let goal: WeeklyGoalStatus
    let franchise: (used: Double, limit: Double, excessCost: Double)?

    init(engine: FinanceEngine, rangeDays: Int, now: Date = Date()) {
        let calendar = Calendar.br
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(rangeDays - 1), to: today) ?? today
        self.rangeDays = rangeDays
        self.since = start
        self.totals = PeriodTotals(engine.breakdowns(since: start))
        self.categories = engine.categoryPerformance(since: start)
        self.profile = engine.tripProfile(since: start)
        self.cpk = engine.costPerKm(now: now)
        self.audit = engine.odometerAudit(since: start)
        self.goal = engine.weeklyGoal(now: now)
        self.franchise = engine.franchiseStatus(now: now)
    }

    var hasData: Bool { totals.days > 0 }

    var bestByHour: CategoryPerformance? {
        categories.filter { $0.hours > 0 }.max { $0.netPerHour < $1.netPerHour }
    }

    var bestByKm: CategoryPerformance? {
        categories.filter { $0.km > 0 }.max { $0.netPerKm < $1.netPerKm }
    }

    var categoryVerdict: String {
        guard let hour = bestByHour else {
            return "Lance os ganhos separados por categoria para descobrir qual rende mais."
        }
        var text = "\(hour.category.title) entrega a maior margem líquida por hora"
        if let km = bestByKm, km.category != hour.category {
            text += ", enquanto \(km.category.title) rende mais por km"
        }
        return text + "."
    }

    /// Parcela do bruto que veio de tarifa base (sem dinâmico/promoções e sem gorjetas).
    var baseShare: Double {
        totals.gross > 0 ? max(0, totals.gross - totals.surge - totals.tips) / totals.gross : 0
    }

    var tipShare: Double {
        totals.gross > 0 ? totals.tips / totals.gross : 0
    }

    var surgeVerdict: String {
        let share = totals.surgeShare
        if totals.gross <= 0 { return "Sem dados no período." }
        if share >= 0.30 {
            return "Dependência alta: sem dinâmico e promoções o faturamento cairia quase um terço. Em dias comuns a operação fica frágil."
        }
        if share >= 0.15 {
            return "Dependência moderada: os multiplicadores ajudam, mas a tarifa base ainda sustenta a operação."
        }
        return "Operação saudável: a tarifa base sustenta o resultado mesmo em dias comuns."
    }

    var deadheadVerdict: String {
        guard let share = totals.deadheadShare else {
            return "Informe os km em corrida (com passageiro) nos resumos para medir o km vazio."
        }
        if share > 0.45 { return "Km vazio alto: quase metade do que o pneu roda não é pago. Reposicione-se menos e espere em pontos quentes." }
        if share > 0.30 { return "Km vazio dentro do normal, com espaço para melhorar o posicionamento." }
        return "Ótimo aproveitamento: pouca quilometragem improdutiva."
    }

    var profileVerdict: String {
        let valid = profile.filter { $0.totals.days >= 2 && $0.totals.hours > 0 }
        guard let best = valid.max(by: { $0.totals.netPerHour < $1.totals.netPerHour }) else {
            return "São necessários pelo menos 2 dias em um perfil (com nº de viagens informado) para comparar."
        }
        return "Você lucra mais por hora nos dias de corridas \(best.title.lowercased())."
    }

    var auditVerdict: String {
        guard audit.days > 0 else {
            return "Registre o odômetro inicial e final nos resumos para conferir o GPS."
        }
        let difference = audit.differencePct
        if abs(difference) <= 2 { return "GPS e odômetro batem (diferença de \(Fmt.number(difference, digits: 1))%)." }
        if difference > 0 {
            return "O GPS está contando \(Fmt.number(difference, digits: 1))% a menos que o painel. Aplique o fator de calibração."
        }
        return "O GPS está contando \(Fmt.number(-difference, digits: 1))% a mais que o painel. Aplique o fator de calibração."
    }
}
