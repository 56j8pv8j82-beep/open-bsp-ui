import XCTest
@testable import AgendaVoz

/// Testes unitários do `LocalCommandInterpreter`.
///
/// Todos os testes usam uma `referenceDate` fixa (13/08/2026, quinta-feira,
/// 09:00 em America/Sao_Paulo) para tornarem-se determinísticos independente
/// da data em que forem rodados.
final class CommandParserTests: XCTestCase {

    private let timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    private var referenceDate: Date!
    private var interpreter: LocalCommandInterpreter!

    override func setUp() {
        super.setUp()
        interpreter = LocalCommandInterpreter()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        // Quinta-feira, 13 de agosto de 2026, 09:00 -03:00
        referenceDate = cal.date(from: DateComponents(
            year: 2026, month: 8, day: 13, hour: 9, minute: 0
        ))!
    }

    // MARK: - Helpers

    private func parse(_ phrase: String,
                       defaultDuration: Int = 60,
                       defaultReminder: Int? = 10) async throws -> ParsedEvent {
        try await interpreter.interpret(
            transcript: phrase,
            referenceDate: referenceDate,
            timeZone: timeZone,
            defaultDurationMinutes: defaultDuration,
            defaultReminderMinutes: defaultReminder
        )
    }

    private func components(_ date: Date) -> DateComponents {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
    }

    // MARK: - Casos exigidos

    func testReuniaoAmanhaAs14Horas() async throws {
        let e = try await parse("Reunião amanhã às 14 horas")
        XCTAssertTrue(e.title.lowercased().contains("reunião"), "Título: \(e.title)")
        let c = components(e.startDate!)
        XCTAssertEqual(c.year, 2026)
        XCTAssertEqual(c.month, 8)
        XCTAssertEqual(c.day, 14)
        XCTAssertEqual(c.hour, 14)
        XCTAssertEqual(c.minute, 0)
        XCTAssertEqual(Int(e.endDate!.timeIntervalSince(e.startDate!) / 60), 60)
    }

    func testConsultaMedicaSextaFeiraAs9() async throws {
        let e = try await parse("Consulta médica sexta-feira às 9")
        XCTAssertTrue(e.title.lowercased().contains("consulta"), "Título: \(e.title)")
        let c = components(e.startDate!)
        // 13/08/2026 é quinta; próxima sexta é 14/08.
        XCTAssertEqual(c.day, 14)
        XCTAssertEqual(c.hour, 9)
        XCTAssertEqual(c.minute, 0)
    }

    func testLigarParaJoaoHojeAs17() async throws {
        let e = try await parse("Ligar para João hoje às 17")
        XCTAssertTrue(e.title.lowercased().contains("ligar"), "Título: \(e.title)")
        let c = components(e.startDate!)
        XCTAssertEqual(c.day, 13)
        XCTAssertEqual(c.hour, 17)
        XCTAssertEqual(c.minute, 0)
    }

    func testAudienciaDia20DeAgostoAs13h30() async throws {
        let e = try await parse("Audiência dia 20 de agosto às 13h30")
        XCTAssertTrue(e.title.lowercased().contains("audi"), "Título: \(e.title)")
        let c = components(e.startDate!)
        XCTAssertEqual(c.month, 8)
        XCTAssertEqual(c.day, 20)
        XCTAssertEqual(c.hour, 13)
        XCTAssertEqual(c.minute, 30)
    }

    func testReuniaoComClienteDaquiADuasHoras() async throws {
        let e = try await parse("Reunião com cliente daqui a duas horas")
        XCTAssertTrue(e.title.lowercased().contains("reunião"), "Título: \(e.title)")
        // referenceDate = 09:00 → +2h = 11:00 mesmo dia.
        let c = components(e.startDate!)
        XCTAssertEqual(c.hour, 11)
        XCTAssertEqual(c.day, 13)
    }

    func testMeLembraAmanhaDeEnviarOContrato() async throws {
        let e = try await parse("Me lembra amanhã de enviar o contrato")
        XCTAssertTrue(e.title.lowercased().contains("contrato"), "Título: \(e.title)")
        // Não deu horário: startDate deve ser nil (parser pede confirmação).
        XCTAssertNil(e.startDate, "Sem horário explícito, startDate deveria ficar nil para pedir confirmação")
    }

    func testQuintaAs15hAudienciaDoProcesso() async throws {
        let e = try await parse("Quinta às 15h audiência do processo 5001234")
        // referenceDate = quinta 13/08 → próxima quinta é 20/08.
        let c = components(e.startDate!)
        XCTAssertEqual(c.day, 20)
        XCTAssertEqual(c.hour, 15)
        XCTAssertEqual(c.minute, 0)
        XCTAssertTrue(e.title.lowercased().contains("audi") || e.title.contains("5001234"),
                      "Título: \(e.title)")
    }

    func testDia25As10ReuniaoNoEscritorio() async throws {
        let e = try await parse("Dia 25 às 10 reunião no escritório")
        let c = components(e.startDate!)
        XCTAssertEqual(c.day, 25)
        XCTAssertEqual(c.month, 8) // ainda mês corrente
        XCTAssertEqual(c.hour, 10)
        XCTAssertTrue(e.title.lowercased().contains("reunião"), "Título: \(e.title)")
        // Localização opcional: se detectada, deve conter "escritório".
        if let loc = e.location {
            XCTAssertTrue(loc.lowercased().contains("escrit"), "Local: \(loc)")
        }
    }

    // MARK: - Casos adicionais de robustez

    func testMeioDia() async throws {
        let e = try await parse("Almoço amanhã ao meio-dia")
        let c = components(e.startDate!)
        XCTAssertEqual(c.day, 14)
        XCTAssertEqual(c.hour, 12)
        XCTAssertEqual(c.minute, 0)
    }

    func testDaquiA30Minutos() async throws {
        let e = try await parse("Daqui a 30 minutos me lembrar do bolo no forno")
        XCTAssertNotNil(e.startDate)
        let c = components(e.startDate!)
        XCTAssertEqual(c.hour, 9)
        XCTAssertEqual(c.minute, 30)
    }

    func testDepoisDeAmanha() async throws {
        let e = try await parse("Reunião depois de amanhã às 10 da manhã")
        let c = components(e.startDate!)
        XCTAssertEqual(c.day, 15)
        XCTAssertEqual(c.hour, 10)
    }

    func testFraseVazia() async {
        do {
            _ = try await parse("   ")
            XCTFail("Deveria ter lançado emptyTranscript")
        } catch let err as AppError {
            XCTAssertEqual(err, AppError.emptyTranscript)
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }
    }
}
