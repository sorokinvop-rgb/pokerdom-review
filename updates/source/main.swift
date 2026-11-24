import Cocoa
import Vision
import CoreImage
import ImageIO
import CryptoKit
import Security
let diagnosticMode = CommandLine.arguments.dropFirst().first == "--self-test"
var lastOCR=""
var visibleHands: (String,String)?
func prettyCards(_ s:String)->String { s.split(separator:" ").map { token in let t=String(token); return String(t.dropLast()).replacingOccurrences(of:"T",with:"10") + (["C":"♣","D":"♦","H":"♥","S":"♠"][String(t.suffix(1))] ?? "?") }.joined(separator:" ") }
var archivedShowdown = false
var baseReport=""
var analysisText=""
var savedText=""
func refreshReport(){ summary.stringValue = baseReport.components(separatedBy:"\n").filter { $0.hasPrefix("Банк:") || $0.hasPrefix("Формат:") || $0.hasPrefix("Возможная выплата:") }.joined(separator:"   •   "); handsLabel.stringValue = visibleHands.map { "Открытые карты: слева сверху \(prettyCards($0.1))  •  слева снизу \(prettyCards($0.0))" } ?? "Открытые карты: не подтверждены"; output.string = [baseReport,analysisText,savedText].filter{ !$0.isEmpty }.joined(separator:"\n\n") }
func imageDigest(_ url:URL)throws->String { SHA256.hash(data:try Data(contentsOf:url)).map{String(format:"%02x",Int($0))}.joined() }
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let reviewIconBase64 = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAMAAABEpIrGAAAAYFBMVEUZLScLXScIoDUd41vW3NNfaGeUmpqe1K4frUtr4Y670cM5R0R2koNZpG/ZWFtNznQ2PUK6DxLmlZfJKi97eYHQPULffYD8/PwLFxgDCAsYJSXo6OgU1lDT1ta1t7gFmTBCfxLuAAAAIHRSTlP//////v/7//////////////////////3////9//39/z/7UqkAAAHoSURBVHjabZTbmpwgEIS7ERCPc9gkIAi8/1umGp0ZN1k+Lxz7V7qqiyH/fWmtvz+gy322Q9eWKekHQBuKe6u7ECeb/gGSIaLoum7fO6YY41S+AeMUUY/EJNyx7AWw58OwtRWOH/YN9Bw+5RDCgQQ3noDuZNuA0lTKbA4wSkP6AG5ojeVpaB6kYibaNoKeoQH9vu8qbNFYbPpcT0sMcSefAABlioyoKl6v69ujwvs+AOg7KEcp+zz6df36WG1U5wAsSilK3pgERvvnBYAlmfw9EIUCwNikf/95vuspQnEhTZHCZvyctPX68fh6A0UssaSjAOjVGohYH5cdTgAWwYOcaAOQDg16GCDwBTRvLcZZ3i9Dmc8wjslSa0Wa8HM+qnh7UDdvYaaKmjw1IKR0ZkQ71eOSFhxTItwgBdtWsky378deub5WtBCcCwZGjQynsIcWwKlhrguYZKnbaSsyCweAN7KYvq5VPr+wMRgEi3qZJgAVg8mSHNUuYoyBg2RK8rBUVTlM0mA/6mUiUt1e0TydiUpcK2/3nLO2v0xk5TrFoq28MpmZJYsYGjFXaUnKl9D6MZ5xBsDcnDnrr3OR7w0gxS/iPBafozfDrI2Rrtp2MPm/s5mBVMSzomNTfjzdfuyH222Z++s/wF9l4kVzL+BofQAAAABJRU5ErkJggg=="
if let iconData = Data(base64Encoded:reviewIconBase64), let icon = NSImage(data:iconData) { app.applicationIconImage = icon }
let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:850),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
window.title="Pokerdom Review 2.5 — архив раздач"
let root=NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing=12; root.edgeInsets=NSEdgeInsets(top:16,left:16,bottom:16,right:16)
window.contentView=root
let intro=NSTextField(wrappingLabelWithString:"Версия 2.5. Откройте сохранённый скриншот завершённой раздачи. Распознавание локальное; карты и суммы требуют проверки. Программа не подключается к игровому столу.")
root.addArrangedSubview(intro)
let summary=NSTextField(wrappingLabelWithString:"Выберите сохранённую раздачу"); summary.font = .systemFont(ofSize:18,weight:.semibold); root.addArrangedSubview(summary)
let handsLabel=NSTextField(wrappingLabelWithString:"Открытые карты: не подтверждены"); root.addArrangedSubview(handsLabel)
let preview=NSImageView(); preview.imageScaling = .scaleProportionallyUpOrDown; root.addArrangedSubview(preview); preview.heightAnchor.constraint(equalToConstant:310).isActive=true; preview.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-32).isActive=true
let output=NSTextView(); output.isEditable=false; output.font=NSFont.monospacedSystemFont(ofSize:13,weight:.regular)
let scroll=NSScrollView(); scroll.documentView=output; scroll.hasVerticalScroller=true; root.addArrangedSubview(scroll); scroll.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-32).isActive=true; scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:180).isActive=true
func extract(_ text:String,_ pattern:String)->String? {
 guard let regex=try? NSRegularExpression(pattern:pattern,options:[.caseInsensitive]), let m=regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)), let r=Range(m.range(at:1),in:text) else{return nil}; return String(text[r])
}
final class DiagnosticsAction:NSObject, URLSessionTaskDelegate {
 static let shared=DiagnosticsAction()
 private let service="local.pokerdom.review.github.diagnostics"
 private let enabledKey="githubDiagnostics230"
 private var sending=false
 private var lastSent=Date.distantPast
 private var pending:DiagnosticEvent?
 private var timer:Timer?
 private var enabled:Bool {UserDefaults.standard.bool(forKey:enabledKey)}
 private var query:[String:Any] {[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"github-token"]}
 private func token()->String? {
  var q=query; q[kSecReturnData as String]=true; q[kSecMatchLimit as String]=kSecMatchLimitOne
  var result:CFTypeRef?; guard SecItemCopyMatching(q as CFDictionary,&result)==errSecSuccess,let data=result as? Data else{return nil}; return String(data:data,encoding:.utf8)
 }
 private func store(_ token:String)->Bool {
  let data=Data(token.utf8); let status=SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
  if status==errSecSuccess{return true}; guard status==errSecItemNotFound else{return false}
  var q=query; q[kSecValueData as String]=data; return SecItemAdd(q as CFDictionary,nil)==errSecSuccess
 }
 private lazy var session:URLSession = {let c=URLSessionConfiguration.ephemeral;c.httpShouldSetCookies=false;c.urlCache=nil;return URLSession(configuration:c,delegate:self,delegateQueue:nil)}()
 func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void){completionHandler(nil)}
 @objc func configure(){
  let a=NSAlert(); a.messageText="Публичная диагностика GitHub"; a.informativeText="Отчёты в Issue #1 публичны и привязаны к вашему GitHub-аккаунту. Только версия, технический статус и количества распознанных элементов. Без карт, сумм, имён, путей, OCR и изображений. Токен хранится в Связке ключей macOS. Используйте fine-grained token только для pokerdom-review, Issues: Read and write."
  a.addButton(withTitle:"Подключить");a.addButton(withTitle:"Отключить");a.addButton(withTitle:"Отмена")
  let field=NSSecureTextField(frame:NSRect(x:0,y:0,width:340,height:24));field.placeholderString="GitHub fine-grained token";a.accessoryView=field
  let choice=a.runModal()
  if choice == .alertSecondButtonReturn {UserDefaults.standard.set(false,forKey:enabledKey);pending=nil;timer?.invalidate();timer=nil;SecItemDelete(query as CFDictionary);updateStatus();return}
  guard choice == .alertFirstButtonReturn else{return}
  let value=field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
  guard value.hasPrefix("github_pat_"),store(value) else{diagnosticStatus.stringValue="GitHub: нужен fine-grained token / ошибка Keychain";return}
  UserDefaults.standard.set(true,forKey:enabledKey);lastSent=Date.distantPast;publish(DiagnosticEvent(status:.connected));
 }
 func updateStatus(){diagnosticStatus.stringValue=enabled ? "GitHub: включён" : "GitHub: выключен"}
 func publish(_ event:DiagnosticEvent){
  guard !diagnosticMode,enabled else{return};pending=event;flush()
 }
 private func flush(){
  guard enabled,!sending,let event=pending else{return}
  let delay=60-Date().timeIntervalSince(lastSent)
  if delay>0 {if timer==nil {timer=Timer.scheduledTimer(withTimeInterval:delay,repeats:false){[weak self] _ in self?.timer=nil;self?.flush()}};return}
  guard let secret=token() else{diagnosticStatus.stringValue="GitHub: настройте токен";return}
  let url=URL(string:"https://api.github.com/repos/sorokinvop-rgb/pokerdom-review/issues/1/comments")!
  var request=URLRequest(url:url,timeoutInterval:20);request.httpMethod="POST";request.setValue("Bearer "+secret,forHTTPHeaderField:"Authorization");request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept");request.setValue("application/json",forHTTPHeaderField:"Content-Type");request.setValue("PokerdomReview/2.5",forHTTPHeaderField:"User-Agent");request.httpBody=try? JSONSerialization.data(withJSONObject:["body":event.body])
  pending=nil;sending=true;lastSent=Date();diagnosticStatus.stringValue="GitHub: отправка…"
  session.dataTask(with:request){[weak self] _,response,error in
   let code=(response as? HTTPURLResponse)?.statusCode ?? 0
   DispatchQueue.main.async {guard let self=self else{return};self.sending=false;guard self.enabled else{return};if code==201 && error==nil {diagnosticStatus.stringValue="GitHub: отчёт доставлен"}else{diagnosticStatus.stringValue=code==0 ? "GitHub: сеть недоступна" : "GitHub: HTTP \(code)"};self.flush()}
  }.resume()
 }
}
class Actions:NSObject {
 var archive:URL?
 @objc func history(){ let panel=NSOpenPanel(); panel.directoryURL=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Pokerdom Review"); panel.allowedFileTypes=["txt"]; guard panel.runModal() == .OK, let url=panel.url, let report=try? String(contentsOf:url,encoding:.utf8) else{return}; visibleHands=nil; archivedShowdown=false; heroField.stringValue=""; oppField.stringValue=""; boardField.stringValue=""; preview.image=nil; baseReport=report; analysisText=""; savedText="Архивный отчёт"; refreshReport() }
 var timer:Timer?
 var processed=Set<String>()
 var pending=Set<String>()
 @objc func showOCR(){ let alert=NSAlert(); alert.messageText="Исходный OCR"; alert.informativeText=lastOCR; alert.runModal() }
 @objc func journal(){ let dir=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Pokerdom Review"); try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true,attributes:nil); NSWorkspace.shared.open(dir) }
 @objc func watch(){ let panel=NSOpenPanel(); panel.message="Выберите отдельную папку только с завершёнными раздачами"; panel.canChooseFiles=false; panel.canChooseDirectories=true; guard panel.runModal() == .OK, let dir=panel.url else{return}; archive=dir; pending.removeAll(); timer?.invalidate(); timer=Timer.scheduledTimer(timeInterval:15,target:self,selector:#selector(scan),userInfo:nil,repeats:true); status.stringValue="Архив: \(dir.lastPathComponent)"; scan() }
 @objc func stop(){timer?.invalidate(); timer=nil; archive=nil; status.stringValue="Автоимпорт выключен"}
 @objc func scan(){guard let dir=archive else{return}; let files=(try? FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil)) ?? []; var current=Set<String>(); for url in files where ["png","jpg","jpeg"].contains(url.pathExtension.lowercased()) { guard let digest=try? imageDigest(url) else{continue}; current.insert(digest); if pending.contains(digest) && !processed.contains(digest){process(url); processed.insert(digest)} }; pending=current }


 @objc func open(){
 let panel=NSOpenPanel(); panel.allowedFileTypes=["png","jpg","jpeg"]; guard panel.runModal() == .OK, let url=panel.url else{return}
 process(url)
 }
 @objc func folder(){
 let panel=NSOpenPanel(); panel.canChooseFiles=false; panel.canChooseDirectories=true; guard panel.runModal() == .OK, let dir=panel.url else{return}
 let files=(try? FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:nil)) ?? []
 var count=0
 var batch=[String]()
 var hashes=Set<String>()
 for url in files.sorted(by:{$0.path<$1.path}) where ["png","jpg","jpeg"].contains(url.pathExtension.lowercased()) { guard let digest=try? imageDigest(url), hashes.insert(digest).inserted else{continue}; process(url); count += 1; batch.append(url.lastPathComponent+"\n"+baseReport) }
 heroField.stringValue=""; oppField.stringValue=""; boardField.stringValue=""; preview.image=nil; baseReport="Пакет: \(count) уникальных файлов\n\n"+batch.joined(separator:"\n\n────────\n\n"); analysisText=""; savedText=""; visibleHands=nil; archivedShowdown=false; refreshReport()
 }
 func process(_ url:URL){
 visibleHands=nil; archivedShowdown=false; heroField.stringValue=""; oppField.stringValue=""; boardField.stringValue=""; format.state = .off; preview.image=NSImage(contentsOf:url); baseReport=""; analysisText=""; savedText=""; summary.stringValue="Распознавание…"; output.string="Распознавание…"
 let request=VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.recognitionLanguages=["ru-RU","en-US"]; request.usesLanguageCorrection=false
 do {
 try VNImageRequestHandler(url:url,options:[:]).perform([request])
 let lines=(request.results ?? []).compactMap{$0.topCandidates(1).first?.string}
 let raw=lines.joined(separator:"\n")
 if raw.contains("Проверить обновления") && raw.contains("Установить ZIP") { lastOCR=raw; baseReport="Выбран снимок приложения, а не исходный снимок стола."; refreshReport(); return }
 let bankLines=(request.results ?? []).filter { obs in
   let r=obs.boundingBox; return r.midX > 0.25 && r.midX < 0.75 && r.midY > 0.55 && r.midY < 0.75
 }.compactMap{$0.topCandidates(1).first?.string}
 let bank=extract(bankLines.joined(separator:"\n"),#"(?:банк|pot)[ \t]*[:：]?[ \t]*([0-9]+(?:[ \u00a0\u202f][0-9]{3})*(?:[.,][0-9]{1,2})?)(?![0-9.,])"#) ?? "не распознан"
 let foundCombos=lines.filter{line in ["фулл-хаус","две пары","стрит","флеш","каре","тройка","сет","пара"].contains{line.lowercased().contains($0)}}
 var seen=Set<String>()
 let combos=foundCombos.filter{seen.insert($0.lowercased().trimmingCharacters(in:.whitespaces)).inserted}
 let initialGame=detectGameFormat(raw)
 let game=initialGame == "не определён" ? detectGameFormat(readGameCaption(url)) : initialGame
 let shortDeck=game == "6+ Холдем"
 let omaha=game == "Омаха"
 format.state = shortDeck ? .on : .off
 let seats:[(String,Double,Double)] = [("Слева сверху",0.14,0.635),("Сверху",0.50,0.75),("Справа сверху",0.85,0.635),("Слева снизу",0.13,0.285),("Справа снизу",0.87,0.285),("Снизу",0.50,0.135)]
 var recognizedStacks=0
 let stackCandidates=seats.map { seat -> String in
   let explicitZero = (request.results ?? []).contains { obs in
     let r=obs.boundingBox
     guard abs(r.midX-seat.1)<0.10, abs(r.midY-seat.2)<0.035, let t=obs.topCandidates(1).first?.string else{return false}
     return extract(t,#"^\s*(0)[ \t]*(?:[рpРP][.]?|₽|руб[.]?)\s*$"#) != nil
   }
   let value=readSeatStack(url, x:seat.1, y:seat.2) ?? (explicitZero ? "0" : nil)
   if value != nil { recognizedStacks += 1 }
   return "\(seat.0): \(value ?? "не распознан")"
 }
 let detected = (omaha || combos.count < 2 || game == "не определён") ? nil : recognizeArchivedCards(url)
 if let (a,c,b)=detected, !hasActiveAction(lines) { boardField.stringValue=b; visibleHands=(a,c) }
 archivedShowdown = game != "не определён" && !omaha && combos.count >= 2 && detected != nil && !hasActiveAction(lines)
 let payoutLines = (request.results ?? []).filter { obs in
   let r=obs.boundingBox; return r.midX > 0.20 && r.midX < 0.80 && r.midY > 0.32 && r.midY < 0.46
 }.compactMap{$0.topCandidates(1).first?.string}.compactMap{extract($0,#"^\s*([0-9]+(?:[ \u00a0\u202f][0-9]{3})*(?:[.,][0-9]{1,2})?)[ \t]*(?:[рpРP][.]?|₽)\s*$"#)}
 let payout = archivedShowdown && payoutLines.count == 1 ? payoutLines[0] : "не подтверждён"
 let cardReport = omaha ? "Омаха: автоматический разбор карт пока не поддерживается." : !archivedShowdown ? "Карты: завершённая раздача не подтверждена." : "Карты (предварительно): слева снизу \(detected!.0); слева сверху \(detected!.1); стол \(detected!.2). Личные карты не установлены."
 let report="Файл: \(url.lastPathComponent)\nБанк: \(bank)\nФормат: \(game)\nКомбинации: \(combos.isEmpty ? "не распознаны" : combos.joined(separator:"; "))\nСтеки: распознано \(recognizedStacks) из \(seats.count) (проверьте):\n\(stackCandidates.joined(separator: "\n"))\nВозможная выплата: \(payout)\n\(cardReport)\nСтатус: \(archivedShowdown ? "кандидат на завершённую раздачу" : "завершение не подтверждено; личные карты не установлены")"
 if archivedShowdown { analysisText = "Сверьте карты и формат игры. Укажите личные карты только если они вам известны." }
 lastOCR=raw
 baseReport=report; refreshReport()
 if diagnosticMode { return }
 let dir=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Pokerdom Review")
 do {try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true,attributes:nil); try (report+"\n\n"+analysisText).write(to:dir.appendingPathComponent((try imageDigest(url))+".txt"),atomically:true,encoding:.utf8); savedText="Отчёт сохранён в Документы/Pokerdom Review"; DiagnosticsAction.shared.publish(DiagnosticEvent(status:archivedShowdown ? .completed : .unconfirmed, stacks:recognizedStacks, cards:archivedShowdown ? 9 : 0, bank:bank != "не распознан", payout:payout != "не подтверждён")); refreshReport()} catch {output.string += "\n\nНе удалось сохранить отчёт: \(error.localizedDescription)"}
 } catch {output.string="Ошибка: \(error.localizedDescription)"; DiagnosticsAction.shared.publish(DiagnosticEvent(status:.recognitionError))}
 }
}
let fields=NSStackView(); fields.orientation = .horizontal
let heroField=NSTextField(string: ""); heroField.placeholderString="Ваши карты"
let oppField=NSTextField(string: ""); oppField.placeholderString="Карты соперника"
let boardField=NSTextField(string: ""); boardField.placeholderString="Карты стола"
let format=NSButton(checkboxWithTitle:"6+",target:nil,action:nil)
for f in [heroField,oppField,boardField] {f.widthAnchor.constraint(equalToConstant:f === boardField ? 220:140).isActive=true; fields.addArrangedSubview(f)}
fields.addArrangedSubview(format)
class MathAction:NSObject { @objc func calculate(){guard archivedShowdown else {analysisText="Разбор доступен только для подтверждённой завершённой раздачи Холдема."; refreshReport(); return}; guard let h=parseCards(heroField.stringValue),let o=parseCards(oppField.stringValue),let b=parseCards(boardField.stringValue) else {output.string += "\nПроверьте формат карт: KS KD (C/D/H/S).";return}; analysisText=retrospective(h,o,b,short:format.state == .on); refreshReport() } }
let mathAction=MathAction(); fields.addArrangedSubview(NSButton(title:"Разбор",target:mathAction,action:#selector(MathAction.calculate))); root.insertArrangedSubview(fields,at:1)
let actions=Actions(); let button=NSButton(title:"Открыть скриншот",target:actions,action:#selector(Actions.open)); let controls=NSStackView(views:[button,NSButton(title:"Папка раздач",target:actions,action:#selector(Actions.folder)),NSButton(title:"Показать OCR",target:actions,action:#selector(Actions.showOCR))]); root.insertArrangedSubview(controls,at:1)
let status=NSTextField(labelWithString:"Автоимпорт выключен")
let archiveControls=NSStackView(views:[NSButton(title:"Следить за архивом",target:actions,action:#selector(Actions.watch)),NSButton(title:"Остановить",target:actions,action:#selector(Actions.stop)),NSButton(title:"Журнал отчётов",target:actions,action:#selector(Actions.journal)),NSButton(title:"История",target:actions,action:#selector(Actions.history)),status]); root.insertArrangedSubview(archiveControls,at:2)
let diagnosticStatus=NSTextField(labelWithString:"GitHub: выключен")
let diagnostics=DiagnosticsAction.shared
root.insertArrangedSubview(NSStackView(views:[NSButton(title:"Журнал GitHub…",target:diagnostics,action:#selector(DiagnosticsAction.configure)),diagnosticStatus]),at:3)
diagnostics.updateStatus()
let updateAction = UpdateAction()
root.insertArrangedSubview(NSStackView(views:[NSButton(title:"Обновить из GitHub",target:updateAction,action:#selector(UpdateAction.checkSource)),NSButton(title:"Установить ZIP…",target:updateAction,action:#selector(UpdateAction.install)),NSButton(title:"Подписанные релизы",target:updateAction,action:#selector(UpdateAction.check))]),at:1)
if diagnosticMode {
 let args = Array(CommandLine.arguments.dropFirst(2))
 guard args.count == 5 else { print("Expected five fixtures"); exit(2) }
 let expected = ["666.38", "666.38", "323.77", "83.16", "33000"]
 var failures = 0
 for (i,path) in args.enumerated() {
  actions.process(URL(fileURLWithPath:path))
  let bankLine = baseReport.components(separatedBy:"\n").first(where:{$0.hasPrefix("Банк:")}) ?? ""
  let bank = bankLine.replacingOccurrences(of:"Банк:",with:"").replacingOccurrences(of:",",with:".").filter{ !$0.isWhitespace }
  let statusOK = archivedShowdown == (i == 0)
  let cardsOK = i == 0 ? (boardField.stringValue == "JD 6S TH 3H 4D" && visibleHands?.0 == "6C 6D" && visibleHands?.1 == "3D 2D") : visibleHands == nil
  let expectedFirst=["Слева сверху: 0","Сверху: 516,33","Справа сверху: 247,70","Слева снизу: 47,44","Справа снизу: 246,79","Снизу: 634,20","Возможная выплата: 631,08","Формат: Холдем"]
  let reportLines=Set(baseReport.components(separatedBy:"\n"))
  let firstDetailsOK=i != 0 || expectedFirst.allSatisfy{reportLines.contains($0)}
  let ok = bank == expected[i] && statusOK && cardsOK && firstDetailsOK
  print("\(ok ? "PASS" : "FAIL") fixture \(i+1): \(bankLine), status=\(archivedShowdown), board=\(boardField.stringValue)")
  if !ok { failures += 1 }
 }
 if failures == 0 {
  do {try cacheUpdateInputs(args.map{URL(fileURLWithPath:$0)})} catch {print("Update cache: \(error.localizedDescription)"); exit(3)}
 }
 exit(failures == 0 ? 0 : 1)
}
diagnostics.publish(DiagnosticEvent(status:.connected))
window.isReleasedWhenClosed=false; window.center(); window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps:true);  app.run()

// Read the numeric line independently at two scales and with enhanced contrast.
func readSeatStack(_ url:URL,x:Double,y:Double)->String? {
 guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else{return nil}
 let w=CGFloat(image.width),h=CGFloat(image.height)
 let region=CGRect(x:max(0,x-0.12)*w,y:max(0,1-y-0.025)*h,width:min(0.28,1-max(0,x-0.12))*w,height:min(0.065,1-max(0,1-y-0.025))*h).integral
 guard let crop=image.cropping(to:region) else{return nil}
 let ci=CIImage(cgImage:crop); let context=CIContext(options:nil)
 let variants=[ci,ci.applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0,kCIInputContrastKey:1.6]),ci.applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0,kCIInputBrightnessKey:0.15,kCIInputContrastKey:1.3])]
 var votes=[String:Int]()
 for variant in variants {
   let scaled=variant.transformed(by:CGAffineTransform(scaleX:3,y:3))
   guard let cg=context.createCGImage(scaled,from:scaled.extent) else{continue}
   let req=VNRecognizeTextRequest(); req.recognitionLevel = .accurate; req.recognitionLanguages=["en-US"]; req.usesLanguageCorrection=false
   guard (try? VNImageRequestHandler(cgImage:cg,options:[:]).perform([req])) != nil else{continue}
   let candidates=(req.results ?? []).compactMap { obs -> (String,CGFloat)? in
      guard let c=obs.topCandidates(1).first,c.confidence >= 0.50 else{return nil}
      let t=c.string.trimmingCharacters(in:.whitespacesAndNewlines)
      guard let amount=extract(t,#"^([0-9]+(?:[ \u00a0\u202f][0-9]{3})*(?:[.,][0-9]{1,2})?)[ \t]*(?:[рpPРrR][.]?|₽|руб[.]?)?$"#) else{return nil}
      let n=amount.filter{ !$0.isWhitespace }.replacingOccurrences(of:".",with:",")
      let distance=abs(obs.boundingBox.midY - 0.5)
      return (n,distance)
   }.sorted{$0.1 < $1.1}
   if let first=candidates.first, candidates.count == 1 || candidates[1].1-first.1 > 0.12 {votes[first.0,default:0]+=1}
 }
 let ordered=votes.sorted{$0.value > $1.value}; guard let first=ordered.first,first.value>=2,ordered.count==1 || first.value>ordered[1].value else{return nil}; return first.key
}

// Separate OCR pass for the caption below the board; no inference from stakes or card counts.
func readGameCaption(_ url:URL)->String {
 guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else{return ""}
 let w=CGFloat(image.width),h=CGFloat(image.height)
 let rect=CGRect(x:0.34*w,y:0.55*h,width:0.32*w,height:0.15*h).integral
 guard let crop=image.cropping(to:rect) else{return ""}
 let ci=CIImage(cgImage:crop).applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0,kCIInputContrastKey:1.6]).transformed(by:CGAffineTransform(scaleX:3,y:3))
 guard let cg=CIContext().createCGImage(ci,from:ci.extent) else{return ""}
 let req=VNRecognizeTextRequest(); req.recognitionLevel = .accurate; req.recognitionLanguages=["ru-RU","en-US"]; req.usesLanguageCorrection=false
 guard (try? VNImageRequestHandler(cgImage:cg,options:[:]).perform([req])) != nil else{return ""}
 return (req.results ?? []).compactMap{$0.topCandidates(1).first?.string}.joined(separator:"\n")
}
