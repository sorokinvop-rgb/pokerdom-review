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
var archivedOmahaCandidate = false
var manualReviewGame:String? = nil
var baseReport=""
var analysisText=""
var savedText=""
func refreshReport(){ let headline=baseReport.components(separatedBy:"\n").filter { $0.hasPrefix("Банк:") || $0.hasPrefix("Формат:") || $0.hasPrefix("Возможная выплата:") }.joined(separator:"   •   "); summary.stringValue = headline.isEmpty ? (baseReport.components(separatedBy:"\n").first ?? "") : headline; handsLabel.stringValue = visibleHands.map { "Открытые карты: слева сверху \(prettyCards($0.1))  •  слева снизу \(prettyCards($0.0))" } ?? "Открытые карты: не подтверждены"; output.string = [baseReport,analysisText,savedText].filter{ !$0.isEmpty }.joined(separator:"\n\n") }
func imageDigest(_ url:URL)throws->String { SHA256.hash(data:try Data(contentsOf:url)).map{String(format:"%02x",Int($0))}.joined() }
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let reviewIconBase64 = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAMAAABEpIrGAAAAYFBMVEUZLScLXScIoDUd41vW3NNfaGeUmpqe1K4frUtr4Y670cM5R0R2koNZpG/ZWFtNznQ2PUK6DxLmlZfJKi97eYHQPULffYD8/PwLFxgDCAsYJSXo6OgU1lDT1ta1t7gFmTBCfxLuAAAAIHRSTlP//////v/7//////////////////////3////9//39/z/7UqkAAAHoSURBVHjabZTbmpwgEIS7ERCPc9gkIAi8/1umGp0ZN1k+Lxz7V7qqiyH/fWmtvz+gy322Q9eWKekHQBuKe6u7ECeb/gGSIaLoum7fO6YY41S+AeMUUY/EJNyx7AWw58OwtRWOH/YN9Bw+5RDCgQQ3noDuZNuA0lTKbA4wSkP6AG5ojeVpaB6kYibaNoKeoQH9vu8qbNFYbPpcT0sMcSefAABlioyoKl6v69ujwvs+AOg7KEcp+zz6df36WG1U5wAsSilK3pgERvvnBYAlmfw9EIUCwNikf/95vuspQnEhTZHCZvyctPX68fh6A0UssaSjAOjVGohYH5cdTgAWwYOcaAOQDg16GCDwBTRvLcZZ3i9Dmc8wjslSa0Wa8HM+qnh7UDdvYaaKmjw1IKR0ZkQ71eOSFhxTItwgBdtWsky378deub5WtBCcCwZGjQynsIcWwKlhrguYZKnbaSsyCweAN7KYvq5VPr+wMRgEi3qZJgAVg8mSHNUuYoyBg2RK8rBUVTlM0mA/6mUiUt1e0TydiUpcK2/3nLO2v0xk5TrFoq28MpmZJYsYGjFXaUnKl9D6MZ5xBsDcnDnrr3OR7w0gxS/iPBafozfDrI2Rrtp2MPm/s5mBVMSzomNTfjzdfuyH222Z++s/wF9l4kVzL+BofQAAAABJRU5ErkJggg=="
if let iconData = Data(base64Encoded:reviewIconBase64), let icon = NSImage(data:iconData) { app.applicationIconImage = icon }
let window = NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:850),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
window.title="Pokerdom Review 2.9 — архив раздач"
let root=NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing=12; root.edgeInsets=NSEdgeInsets(top:16,left:16,bottom:16,right:16)
window.contentView=root
let intro=NSTextField(wrappingLabelWithString:"Версия 2.9. Откройте сохранённый скриншот завершённой раздачи. Распознавание локальное; карты и суммы требуют проверки. Программа не подключается к игровому столу.")
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
 private let queueKey="githubDiagnosticsQueue270"
 private var sending=false
 private var generation=0
 private var lastSent=Date.distantPast
 private var cachedToken:String?
 private var attemptedSilentRead=false
 private lazy var pending=DiagnosticQueue.restore(UserDefaults.standard.data(forKey:queueKey))
 private var timer:Timer?
 private var enabled:Bool {UserDefaults.standard.bool(forKey:enabledKey)}
 private var query:[String:Any] {[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"github-token"]}
 private func persist(){UserDefaults.standard.set(try? JSONEncoder().encode(pending.events),forKey:queueKey)}
 private func token(interactive:Bool)->String? {
  if let secret=cachedToken {return secret}
  if !interactive && attemptedSilentRead {return nil}
  attemptedSilentRead=true
  var q=query; q[kSecReturnData as String]=true; q[kSecMatchLimit as String]=kSecMatchLimitOne
  if !interactive {q[kSecUseAuthenticationUI as String]=kSecUseAuthenticationUIFail}
  var result:CFTypeRef?; guard SecItemCopyMatching(q as CFDictionary,&result)==errSecSuccess,let data=result as? Data,let secret=String(data:data,encoding:.utf8),secret.hasPrefix("github_pat_") else{return nil}
  cachedToken=secret;return secret
 }
 private func store(_ token:String)->Bool {
  let data=Data(token.utf8); let status=SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
  if status==errSecSuccess{return true}; guard status==errSecItemNotFound else{return false}
  var q=query; q[kSecValueData as String]=data; return SecItemAdd(q as CFDictionary,nil)==errSecSuccess
 }
 private lazy var session:URLSession = {let c=URLSessionConfiguration.ephemeral;c.httpShouldSetCookies=false;c.urlCache=nil;return URLSession(configuration:c,delegate:self,delegateQueue:nil)}()
 func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void){completionHandler(nil)}
 @objc func configure(){
  let a=NSAlert(); a.messageText="Публичная диагностика GitHub"; a.informativeText="Отчёты в Issue #1 публичны и привязаны к вашему аккаунту. Только технические поля. Оставьте поле пустым, чтобы разрешить доступ к сохранённому токену один раз за запуск. Новый токен вводите только при его замене."
  a.addButton(withTitle:"Подключить / разрешить доступ");a.addButton(withTitle:"Отключить");a.addButton(withTitle:"Отмена")
  let field=NSSecureTextField(frame:NSRect(x:0,y:0,width:340,height:24));field.placeholderString="Новый токен (необязательно)";a.accessoryView=field
  let choice=a.runModal()
  if choice == .alertSecondButtonReturn {UserDefaults.standard.set(false,forKey:enabledKey);generation+=1;pending.clear();persist();timer?.invalidate();timer=nil;cachedToken=nil;attemptedSilentRead=true;updateStatus();return}
  guard choice == .alertFirstButtonReturn else{return}
  let value=field.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
  if value.isEmpty {guard token(interactive:true) != nil else {diagnosticStatus.stringValue="GitHub: доступ не разрешён; очередь сохранена";return}}
  else {guard value.hasPrefix("github_pat_"),store(value) else {diagnosticStatus.stringValue="GitHub: ошибка сохранения токена";return};cachedToken=value;attemptedSilentRead=true}
  UserDefaults.standard.set(true,forKey:enabledKey);lastSent=Date.distantPast;publish(DiagnosticEvent(status:.connected));flush()
 }
 func updateStatus(){diagnosticStatus.stringValue=enabled ? "GitHub: включён" : "GitHub: выключен"}
 func publish(_ event:DiagnosticEvent){
  guard !diagnosticMode,enabled else{return};guard pending.append(event) else{diagnosticStatus.stringValue="GitHub: очередь заполнена; отчёт остался локально";flush();return};persist();flush()
 }
 private func flush(){
  guard enabled,!sending,!pending.events.isEmpty else{return}
  let delay=60-Date().timeIntervalSince(lastSent)
  if delay>0 {if timer==nil {timer=Timer.scheduledTimer(withTimeInterval:delay,repeats:false){[weak self] _ in self?.timer=nil;self?.flush()}};return}
  guard let secret=token(interactive:false) else{diagnosticStatus.stringValue="GitHub: разрешите доступ через Журнал GitHub…";return}
  let events=pending.batch(), currentGeneration=generation
  let url=URL(string:"https://api.github.com/repos/sorokinvop-rgb/pokerdom-review/issues/1/comments")!
  var request=URLRequest(url:url,timeoutInterval:20);request.httpMethod="POST";request.setValue("Bearer "+secret,forHTTPHeaderField:"Authorization");request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept");request.setValue("application/json",forHTTPHeaderField:"Content-Type");request.setValue("PokerdomReview/2.9",forHTTPHeaderField:"User-Agent");request.httpBody=try? JSONSerialization.data(withJSONObject:["body":events.map{$0.body}.joined(separator:"\n\n---\n\n")])
  sending=true;lastSent=Date();diagnosticStatus.stringValue="GitHub: отправка \(events.count) отчётов…"
  session.dataTask(with:request){[weak self] _,response,error in
   let code=(response as? HTTPURLResponse)?.statusCode ?? 0
   DispatchQueue.main.async {
    guard let self=self else{return};self.sending=false
    guard self.enabled else{return};guard self.generation==currentGeneration else{self.flush();return}
    if code==201 && error==nil {self.pending.acknowledge(events.count);self.persist();diagnosticStatus.stringValue="GitHub: доставлено \(events.count); в очереди \(self.pending.events.count)"}
    else {diagnosticStatus.stringValue="GitHub: HTTP \(code); очередь сохранена";if code==401 || code==403 || code==404 {self.cachedToken=nil;self.attemptedSilentRead=true;return}}
    self.flush()
   }
  }.resume()
 }
}
class Actions:NSObject {
 var archive:URL?
 @objc func history(){ let panel=NSOpenPanel(); panel.directoryURL=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Pokerdom Review"); panel.allowedFileTypes=["txt"]; guard panel.runModal() == .OK, let url=panel.url, let report=try? String(contentsOf:url,encoding:.utf8) else{return}; lastOCR=""; visibleHands=nil; archivedShowdown=false; archivedOmahaCandidate=false; manualReviewGame=nil; heroField.stringValue=""; oppField.stringValue=""; boardField.stringValue=""; preview.image=nil; baseReport=report; analysisText=""; savedText="Архивный отчёт"; refreshReport() }
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
 heroField.stringValue=""; oppField.stringValue=""; boardField.stringValue=""; preview.image=nil; lastOCR=""; baseReport="Пакет: \(count) уникальных файлов\n\n"+batch.joined(separator:"\n\n────────\n\n"); analysisText=""; savedText=""; visibleHands=nil; archivedShowdown=false; archivedOmahaCandidate=false; manualReviewGame=nil; refreshReport()
 }
 func process(_ url:URL){
 lastOCR=""; visibleHands=nil; archivedShowdown=false; archivedOmahaCandidate=false; manualReviewGame=nil; heroField.stringValue=""; oppField.stringValue=""; boardField.stringValue=""; format.state = .off; preview.image=NSImage(contentsOf:url); baseReport=""; analysisText=""; savedText=""; summary.stringValue="Распознавание…"; output.string="Распознавание…"
 let request=VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.recognitionLanguages=["ru-RU","en-US"]; request.usesLanguageCorrection=false
 do {
 guard let original=loadArchiveImage(url) else {throw NSError(domain:"Archive image",code:1,userInfo:[NSLocalizedDescriptionKey:"Не удалось открыть изображение"])}
 let image=cropArchiveImage(original) ?? original
 try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
 let lines=(request.results ?? []).compactMap{$0.topCandidates(1).first?.string}
 let raw=lines.joined(separator:"\n")
 if isReviewWindow(raw) { lastOCR=raw; baseReport="Выбран снимок приложения, а не исходный снимок стола."; refreshReport(); DiagnosticsAction.shared.publish(DiagnosticEvent(status:.unconfirmed,reason:.notTableImage)); return }
 let bankLines=(request.results ?? []).filter { obs in
   let r=obs.boundingBox; return r.midX > 0.25 && r.midX < 0.75 && r.midY > 0.55 && r.midY < 0.75
 }.compactMap{$0.topCandidates(1).first?.string}
 let bank=extract(bankLines.joined(separator:"\n"),#"(?:банк|pot)[ \t]*[:：]?[ \t]*([0-9]+(?:[ \u00a0\u202f][0-9]{3})*(?:[.,][0-9]{1,2})?)(?![0-9.,])"#) ?? "не распознан"
 let markerObservations=(request.results ?? []).compactMap { obs -> (String,Double,Double)? in
  guard let text=obs.topCandidates(1).first?.string else{return nil}
  return (text,Double(obs.boundingBox.midX),Double(obs.boundingBox.midY))
 }
 let markers=distinctShowdownMarkers(markerObservations)
 let combos=markers.map{$0.0}
 let initialGame=detectGameFormat(raw)
 let game=initialGame == "не определён" ? detectGameFormat(readGameCaption(image)) : initialGame
 let shortDeck=game == "6+ Холдем"
 let omaha=game == "Омаха"
 format.state = shortDeck ? .on : .off
 let seats:[(String,Double,Double)] = [("Слева сверху",0.14,0.635),("Сверху",0.50,0.75),("Справа сверху",0.85,0.635),("Слева снизу",0.13,0.285),("Справа снизу",0.87,0.285),("Снизу",0.50,0.135)]
 let stackObservations=(request.results ?? []).compactMap { obs -> StackObservation? in
  guard let candidate=obs.topCandidates(1).first else{return nil}
  return StackObservation(text:candidate.string,x:Double(obs.boundingBox.midX),y:Double(obs.boundingBox.midY),confidence:Double(candidate.confidence))
 }
 func readStacks(_ positions:[(String,Double,Double)], tournament:Bool=false)->(Int,[String]) {
 var count=0
 let values=positions.map { seat -> String in
   let explicitZero = (request.results ?? []).contains { obs in
     let r=obs.boundingBox
     guard abs(r.midX-seat.1)<0.10, abs(r.midY-seat.2)<0.035, let t=obs.topCandidates(1).first?.string else{return false}
     return extract(t,#"^\s*(0)[ \t]*(?:[рpРP][.]?|₽|руб[.]?)\s*$"#) != nil
   }
   let value=readSeatStack(image, x:seat.1, y:seat.2) ?? (explicitZero ? "0" : nil) ?? (tournament ? tournamentStackFromObservations(stackObservations,x:seat.1,y:seat.2) : nil)
   if value != nil {count+=1}
   return "\(seat.0): \(value ?? "не распознан")"
 }
 return (count,values)
 }
 var (recognizedStacks,stackCandidates)=readStacks(seats)
 // Compare a second, explicitly tournament-labelled layout if regular reading is incomplete.
 if recognizedStacks<6, let centers=tournamentStackCenters(raw) {
  let alternative=zip(seats,centers).map { pair in (pair.0.0,pair.1.0,pair.1.1) }
  let candidate=readStacks(alternative,tournament:true)
  if preferTournamentStacks(regular:recognizedStacks,alternate:candidate.0) { (recognizedStacks,stackCandidates)=candidate }
 }
 let active=hasActiveAction(lines)
 let pairConsistent=hasConsistentShowdownPair(combos)
 manualReviewGame=manualArchiveFormat(game:game,labels:combos,active:active)
 archivedOmahaCandidate=manualReviewGame == "Омаха"
 let preliminary=ReviewGate.assess(game:game,markers:combos.count,active:active,cardsRecognized:false)
 let safePreliminary:ReviewGate = preliminary == .cardsUnconfirmed && !pairConsistent ? .ambiguousShowdown : preliminary
 var cardFailure = CardReadFailure.notChecked
 var detected:(String,String,String)? = nil
 if safePreliminary == .cardsUnconfirmed {
  if calibratedShowdownSeats(markers) {detected=recognizeArchivedCards(image,failure:&cardFailure)}
  else {cardFailure = .unsupportedLayout}
 }
 if let (a,c,b)=detected, !validArchivedDeck(a,c,b,short:shortDeck) {detected=nil;cardFailure = .invalidDeck}
 let reason = safePreliminary == .ambiguousShowdown ? safePreliminary : ReviewGate.assess(game:game,markers:combos.count,active:active,cardsRecognized:detected != nil)
 archivedShowdown = reason == .candidate
 if let (a,c,b)=detected, archivedShowdown { boardField.stringValue=b; visibleHands=(a,c) }
 let payoutLines = (request.results ?? []).filter { obs in
   let r=obs.boundingBox; return r.midX > 0.20 && r.midX < 0.80 && r.midY > 0.32 && r.midY < 0.46
 }.compactMap{$0.topCandidates(1).first?.string}.compactMap{extract($0,#"^\s*([0-9]+(?:[ \u00a0\u202f][0-9]{3})*(?:[.,][0-9]{1,2})?)[ \t]*(?:[рpРP][.]?|₽)\s*$"#)}
 let payout = archivedShowdown && payoutLines.count == 1 ? payoutLines[0] : "не подтверждён"
 let cardReport = omaha ? "Омаха: автоматическое чтение карт пока не поддерживается. Для завершённого архивного снимка с признаками вскрытия можно сверить и ввести две открытые руки по 4 карты и стол из 5 карт." : !archivedShowdown ? "Карты: завершённая раздача не подтверждена." : "Карты (предварительно): слева снизу \(detected!.0); слева сверху \(detected!.1); стол \(detected!.2). Личные карты не установлены."
 let report="Файл: \(url.lastPathComponent)\nБанк: \(bank)\nФормат: \(game)\nКомбинации: \(combos.isEmpty ? "не распознаны" : combos.joined(separator:"; "))\nСтеки: распознано \(recognizedStacks) из \(seats.count) (проверьте):\n\(stackCandidates.joined(separator: "\n"))\nВозможная выплата: \(payout)\n\(cardReport)\nСтатус: \(archivedShowdown ? "кандидат на завершённую раздачу" : "завершение не подтверждено; личные карты не установлены")"
 if archivedShowdown { analysisText = "Сверьте карты и формат игры. Укажите личные карты только если они вам известны." }
 else if manualReviewGame != nil {analysisText="Есть согласованные итоговые метки. Автоматическое чтение не подтверждено. Для архивного разбора введите обе видимые руки и все пять общих карт, затем подтвердите завершение."}
 lastOCR=raw
 baseReport=report; refreshReport()
 if diagnosticMode { return }
 let dir=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Pokerdom Review")
 DiagnosticsAction.shared.publish(DiagnosticEvent(status:archivedShowdown ? .completed : .unconfirmed, stacks:recognizedStacks, cards:archivedShowdown ? 9 : 0, bank:bank != "не распознан", payout:payout != "не подтверждён", reason:reason, cardFailure:cardFailure))
 do {try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true,attributes:nil); try (report+"\n\n"+analysisText).write(to:dir.appendingPathComponent((try imageDigest(url))+".txt"),atomically:true,encoding:.utf8); savedText="Отчёт сохранён в Документы/Pokerdom Review"; refreshReport()} catch {savedText="Не удалось сохранить отчёт: \(error.localizedDescription)";refreshReport()}
 } catch {baseReport="Ошибка чтения изображения: \(error.localizedDescription)"; refreshReport(); DiagnosticsAction.shared.publish(DiagnosticEvent(status:.recognitionError))}
 }
}
let fields=NSStackView(); fields.orientation = .horizontal
let heroField=NSTextField(string: ""); heroField.placeholderString="Ваши карты"
let oppField=NSTextField(string: ""); oppField.placeholderString="Карты соперника"
let boardField=NSTextField(string: ""); boardField.placeholderString="Карты стола"
let format=NSButton(checkboxWithTitle:"6+",target:nil,action:nil); format.isEnabled=false
for f in [heroField,oppField,boardField] {f.widthAnchor.constraint(equalToConstant:f === boardField ? 220:140).isActive=true; fields.addArrangedSubview(f)}
fields.addArrangedSubview(format)
class MathAction:NSObject {
 @objc func calculate(){
  guard let reviewGame=manualReviewGame else {analysisText="Разбор доступен только для архивного снимка с признаками завершённой раздачи.";refreshReport();return}
  guard let h=parseCards(heroField.stringValue),let o=parseCards(oppField.stringValue),let b=parseCards(boardField.stringValue) else{analysisText="Проверьте формат карт: KS KD (C/D/H/S).";refreshReport();return}
  if reviewGame == "Омаха" {
   guard let result=confirmedOmahaResult(h,o,b) else{analysisText="Омаха: нужны 13 разных допустимых карт (4 + 4 + 5).";refreshReport();return}
   let confirm=NSAlert();confirm.messageText="Подтвердите завершённую раздачу Омахи";confirm.informativeText="Сверьте все открытые карты с сохранённым изображением. Разбор только после окончания игры.";confirm.addButton(withTitle:"Подтверждаю");confirm.addButton(withTitle:"Отмена")
   guard confirm.runModal() == .alertFirstButtonReturn else{return};analysisText=result
  } else {
   let short=reviewGame == "6+ Холдем"
   guard h.count==2,o.count==2,b.count==5,Set(h+o+b).count==9,(h+o+b).allSatisfy({(short ? 6:2)...14 ~= $0.rank && "CDHS".contains($0.suit)}) else{analysisText="Нужны 9 разных допустимых карт (2 + 2 + 5).";refreshReport();return}
   let confirm=NSAlert();confirm.messageText="Подтвердите завершённую раздачу";confirm.informativeText="Сверьте открытые карты, стол и формат игры с сохранённым изображением. Разбор только после окончания игры.";confirm.addButton(withTitle:"Подтверждаю");confirm.addButton(withTitle:"Отмена")
   guard confirm.runModal() == .alertFirstButtonReturn else{return}
   analysisText=retrospective(h,o,b,short:short)
  }
  refreshReport()
 }
}
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
  let firstDetailsOK=i != 0 || matchingFixtureLines(baseReport,expected:expectedFirst)==expectedFirst.count
  if i == 4 {
   let tournamentExpected=["Слева сверху: 72991","Сверху: 5875","Справа сверху: 26325","Слева снизу: 22250","Справа снизу: 15600","Снизу: 10000"]
   let matches=matchingFixtureLines(baseReport,expected:tournamentExpected)
   print("INFO experimental tournament stack recognition: \(matches)/6 exact fixture values; non-blocking until independently validated")
  }
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
func readSeatStack(_ image:CGImage,x:Double,y:Double)->String? {
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
func readGameCaption(_ image:CGImage)->String {
 let w=CGFloat(image.width),h=CGFloat(image.height)
 let rect=CGRect(x:0.34*w,y:0.55*h,width:0.32*w,height:0.15*h).integral
 guard let crop=image.cropping(to:rect) else{return ""}
 let ci=CIImage(cgImage:crop).applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0,kCIInputContrastKey:1.6]).transformed(by:CGAffineTransform(scaleX:3,y:3))
 guard let cg=CIContext().createCGImage(ci,from:ci.extent) else{return ""}
 let req=VNRecognizeTextRequest(); req.recognitionLevel = .accurate; req.recognitionLanguages=["ru-RU","en-US"]; req.usesLanguageCorrection=false
 guard (try? VNImageRequestHandler(cgImage:cg,options:[:]).perform([req])) != nil else{return ""}
 return (req.results ?? []).compactMap{$0.topCandidates(1).first?.string}.joined(separator:"\n")
}
