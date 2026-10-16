import Foundation

// A small Open Packaging Conventions writer for a single workbook. ZIP entries use
// the standard STORE method: larger files, but no runtime dependency or compression work.
enum TransactionXLSXWriter {
    static func encode(_ selection: TransactionExportSelection, options: TransactionExportOptions) throws -> Data {
        let columns = TransactionExportColumn.selected(options)
        let movementRows = selection.rows.map { row in columns.map { $0.cell(row) } }
        let movementXML = try sheetXML(headers: columns.map(\.title), rows: movementRows,
                                       widths: columns.map(\.width), timeZone: selection.timeZone,
                                       autoFilter: true)
        var entries: [(String, Data)] = []
        let summary = options.includeSummary
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        \(summary ? "<Override PartName=\"/xl/worksheets/sheet2.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" : "")
        </Types>
        """
        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """
        let workbook = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <workbookPr date1904="0"/><sheets><sheet name="Movimenti" sheetId="1" r:id="rId1"/>
        \(summary ? "<sheet name=\"Riepilogo\" sheetId=\"2\" r:id=\"rId2\"/>" : "")
        </sheets></workbook>
        """
        let workbookRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        \(summary ? "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet2.xml\"/>" : "")
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """
        entries.append(("[Content_Types].xml", Data(contentTypes.utf8)))
        entries.append(("_rels/.rels", Data(rootRels.utf8)))
        entries.append(("xl/workbook.xml", Data(workbook.utf8)))
        entries.append(("xl/_rels/workbook.xml.rels", Data(workbookRels.utf8)))
        entries.append(("xl/styles.xml", Data(stylesXML.utf8)))
        entries.append(("xl/worksheets/sheet1.xml", Data(movementXML.utf8)))
        if summary {
            entries.append(("xl/worksheets/sheet2.xml", Data(try summaryXML(selection).utf8)))
        }
        return try StoredZIP.archive(entries)
    }

    private static func summaryXML(_ selection: TransactionExportSelection) throws -> String {
        let total = try selection.totals()
        var rows: [[TransactionExportCell]] = [
            [.text("Transactions"), .integer(total.count)],
            [.text("Personal spending EUR"), .money(total.personal, isEUR: true)],
            [.text("All expenses EUR"), .money(total.expenses, isEUR: true)],
            [.text("Income EUR"), .money(total.income, isEUR: true)],
            [.text("PAC invested EUR"), .money(total.pac, isEUR: true)],
            [.empty, .empty],
            [.text("By category"), .empty],
            summaryHeader
        ]
        for (name, subtotal) in try selection.grouped({ $0.category.isEmpty ? "Uncategorized" : $0.category }) {
            rows.append(summaryRow(name, subtotal))
        }
        rows += [[.empty], [.text("By account")], summaryHeader]
        for (name, subtotal) in try selection.grouped({ $0.account.isEmpty ? "Unspecified" : $0.account }) {
            rows.append(summaryRow(name, subtotal))
        }
        rows += [[.empty], [.text("By month")], summaryHeader]
        for (name, subtotal) in try selection.grouped({ row in
            String(LocalDay(date: row.item.occurredAt, timeZone: selection.timeZone).isoString.prefix(7))
        }) {
            rows.append(summaryRow(name, subtotal))
        }
        return try sheetXML(headers: ["Metric / group", "Value / count", "Personal spending EUR",
                                      "All expenses EUR", "Income EUR", "PAC invested EUR"],
                            rows: rows, widths: [31, 18, 25, 21, 20, 21],
                            timeZone: selection.timeZone, autoFilter: false)
    }

    private static var summaryHeader: [TransactionExportCell] {
        [.text("Group"), .text("Count"), .text("Personal spending EUR"),
         .text("All expenses EUR"), .text("Income EUR"), .text("PAC invested EUR")]
    }

    private static func summaryRow(_ name: String, _ totals: TransactionExportTotals) -> [TransactionExportCell] {
        [.text(name), .integer(totals.count), .money(totals.personal, isEUR: true),
         .money(totals.expenses, isEUR: true), .money(totals.income, isEUR: true),
         .money(totals.pac, isEUR: true)]
    }

    private static func sheetXML(headers: [String], rows: [[TransactionExportCell]], widths: [Double],
                                 timeZone: TimeZone, autoFilter: Bool) throws -> String {
        guard rows.count < 1_048_576, headers.count <= 16_384 else { throw TransactionExportError.tooLarge }
        let lastColumn = columnName(headers.count)
        let lastRow = rows.count + 1
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><dimension ref="A1:\(lastColumn)\(lastRow)"/>
        <sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
        <sheetFormatPr defaultRowHeight="15"/><cols>
        """
        for (index, width) in widths.enumerated() {
            xml += "<col min=\"\(index + 1)\" max=\"\(index + 1)\" width=\"\(width)\" customWidth=\"1\"/>"
        }
        xml += "</cols><sheetData>"
        xml += "<row r=\"1\">"
        for (index, title) in headers.enumerated() {
            xml += try cellXML(.text(title), reference: "\(columnName(index + 1))1", timeZone: timeZone, header: true)
        }
        xml += "</row>"
        for (index, row) in rows.enumerated() {
            try Task.checkCancellation()
            let number = index + 2
            xml += "<row r=\"\(number)\">"
            for (column, value) in row.enumerated() {
                xml += try cellXML(value, reference: "\(columnName(column + 1))\(number)", timeZone: timeZone)
            }
            xml += "</row>"
        }
        xml += "</sheetData>"
        if autoFilter { xml += "<autoFilter ref=\"A1:\(lastColumn)\(lastRow)\"/>" }
        xml += "</worksheet>"
        return xml
    }

    private static func cellXML(_ cell: TransactionExportCell, reference: String,
                                timeZone: TimeZone, header: Bool = false) throws -> String {
        switch cell {
        case .empty: return ""
        case .text(let value):
            return "<c r=\"\(reference)\"\(header ? " s=\"3\"" : "") t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escapeXML(value))</t></is></c>"
        case .money(let cents, let isEUR):
            return "<c r=\"\(reference)\" s=\"\(isEUR ? 4 : 1)\"><v>\(try TransactionExportMoney.xlsxDecimal(cents))</v></c>"
        case .integer(let value):
            return "<c r=\"\(reference)\"><v>\(value)</v></c>"
        case .date(let date):
            return "<c r=\"\(reference)\" s=\"2\"><v>\(excelSerial(date, timeZone: timeZone))</v></c>"
        }
    }

    private static func excelSerial(_ date: Date, timeZone: TimeZone) -> String {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let wallClock = local.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let localAsUTC = utc.date(from: wallClock)!
        let epoch = utc.date(from: DateComponents(year: 1899, month: 12, day: 30))!
        return String(localAsUTC.timeIntervalSince(epoch) / 86_400)
    }

    private static func columnName(_ number: Int) -> String {
        var remaining = number
        var result = ""
        while remaining > 0 {
            remaining -= 1
            result = String(UnicodeScalar(65 + remaining % 26)!) + result
            remaining /= 26
        }
        return result
    }

    private static func escapeXML(_ input: String) -> String {
        var result = ""
        for scalar in input.unicodeScalars {
            let code = scalar.value
            guard code == 9 || code == 10 || code == 13 ||
                    (code >= 0x20 && code <= 0xD7FF) ||
                    (code >= 0xE000 && code <= 0xFFFD) || code >= 0x10000 else { continue }
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default: result.append(String(scalar))
            }
        }
        return result
    }

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
    <numFmts count="3"><numFmt numFmtId="164" formatCode="#,##0.00;[Red]-#,##0.00"/>
    <numFmt numFmtId="165" formatCode="yyyy-mm-dd hh:mm:ss"/>
    <numFmt numFmtId="166" formatCode="#,##0.00 &quot;€&quot;;[Red]-#,##0.00 &quot;€&quot;"/></numFmts>
    <fonts count="2"><font><sz val="11"/><name val="Aptos"/></font>
    <font><b/><sz val="11"/><name val="Aptos"/></font></fonts>
    <fills count="2"><fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFDCF1EF"/><bgColor indexed="64"/></patternFill></fill></fills>
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
    <cellXfs count="5"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
    <xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
    <xf numFmtId="0" fontId="1" fillId="1" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
    <xf numFmtId="166" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>
    """
}

private enum StoredZIP {
    static func archive(_ entries: [(String, Data)]) throws -> Data {
        guard entries.count <= Int(UInt16.max) else { throw TransactionExportError.tooLarge }
        var output = Data()
        var central = Data()
        for (name, contents) in entries {
            try Task.checkCancellation()
            let nameBytes = Data(name.utf8)
            guard nameBytes.count <= Int(UInt16.max), contents.count <= Int(UInt32.max),
                  output.count <= Int(UInt32.max) else { throw TransactionExportError.tooLarge }
            let crc = checksum(contents)
            let offset = UInt32(output.count)
            output.appendLE(UInt32(0x04034B50))
            output.appendLE(UInt16(20)); output.appendLE(UInt16(0x0800))
            output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0))
            output.appendLE(crc); output.appendLE(UInt32(contents.count)); output.appendLE(UInt32(contents.count))
            output.appendLE(UInt16(nameBytes.count)); output.appendLE(UInt16(0))
            output.append(nameBytes); output.append(contents)

            central.appendLE(UInt32(0x02014B50))
            central.appendLE(UInt16(20)); central.appendLE(UInt16(20)); central.appendLE(UInt16(0x0800))
            central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(crc); central.appendLE(UInt32(contents.count)); central.appendLE(UInt32(contents.count))
            central.appendLE(UInt16(nameBytes.count)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt32(0))
            central.appendLE(offset); central.append(nameBytes)
        }
        guard central.count <= Int(UInt32.max), output.count <= Int(UInt32.max) - central.count - 22 else {
            throw TransactionExportError.tooLarge
        }
        let centralOffset = UInt32(output.count)
        output.append(central)
        output.appendLE(UInt32(0x06054B50))
        output.appendLE(UInt16(0)); output.appendLE(UInt16(0))
        output.appendLE(UInt16(entries.count)); output.appendLE(UInt16(entries.count))
        output.appendLE(UInt32(central.count)); output.appendLE(centralOffset)
        output.appendLE(UInt16(0))
        return output
    }

    private static let table: [UInt32] = (0..<256).map { value in
        var result = UInt32(value)
        for _ in 0..<8 { result = result & 1 == 1 ? (result >> 1) ^ 0xEDB88320 : result >> 1 }
        return result
    }

    private static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = (crc >> 8) ^ table[Int((crc ^ UInt32(byte)) & 0xFF)] }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        for shift in 0..<(T.bitWidth / 8) {
            append(UInt8(truncatingIfNeeded: value >> (shift * 8)))
        }
    }
}
