import Foundation
struct Card: Hashable { let rank:Int; let suit:Character }
func parseCards(_ s:String)->[Card]? {
 let ranks=Array("23456789TJQKA"); var result=[Card]()
 for token in s.uppercased().split(whereSeparator:{$0.isWhitespace || $0 == ","}) {
 let normalized=token.replacingOccurrences(of:"10",with:"T").replacingOccurrences(of:"♣",with:"C").replacingOccurrences(of:"♦",with:"D").replacingOccurrences(of:"♥",with:"H").replacingOccurrences(of:"♠",with:"S"); let a=Array(normalized); guard a.count==2, let r=ranks.firstIndex(of:a[0]), "CDHS".contains(a[1]) else{return nil}; result.append(Card(rank:r+2,suit:a[1]))
 }; return result
}
func score5(_ cards:[Card],short:Bool)->[Int] {
 guard cards.count==5,Set(cards).count==5,cards.allSatisfy({(short ? 6:2)...14 ~= $0.rank && "CDHS".contains($0.suit)}) else{return [-1]}
 let r=cards.map{$0.rank}.sorted(by:>); let grouped = Dictionary(grouping:r,by:{$0}); let counts:[(Int,Int)] = grouped.map { ($0.key,$0.value.count) }; let groups = counts.sorted { a,b in if a.1 == b.1 { return a.0 > b.0 }; return a.1 > b.1 }; let flush=Set(cards.map{$0.suit}).count==1
 let straight=Set(r).count==5 ? (r[0]-r[4]==4 ? r[0] : (r == (short ? [14,9,8,7,6] : [14,5,4,3,2]) ? (short ? 9:5):0)):0
 if flush && straight>0{return [8,straight]}; if groups[0].1==4{return [7,groups[0].0,groups[1].0]}; if groups[0].1==3 && groups[1].1==2{return [short ? 5:6,groups[0].0,groups[1].0]}; if flush{return [short ? 6:5]+r}; if straight>0{return [4,straight]}; if groups[0].1==3{return [3]+groups.map{$0.0}}; if groups[0].1==2 && groups[1].1==2{return [2]+groups.map{$0.0}}; if groups[0].1==2{return [1]+groups.map{$0.0}}; return [0]+r
}
func best(_ cards:[Card],short:Bool)->[Int] { guard cards.count==7,Set(cards).count==7,cards.allSatisfy({(short ? 6:2)...14 ~= $0.rank && "CDHS".contains($0.suit)}) else{return [-1]}; var b=[-1]; for i in 0..<cards.count { for j in (i+1)..<cards.count { let s=score5(cards.enumerated().filter{$0.offset != i && $0.offset != j}.map{$0.element},short:short); if b.lexicographicallyPrecedes(s){b=s} } }; return b }
func retrospective(_ hero:[Card],_ opponent:[Card],_ board:[Card],short:Bool)->String {
 let all=hero+opponent+board; guard hero.count==2,opponent.count==2,board.count==5,Set(all).count==9,all.allSatisfy({(short ? 6:2)...14 ~= $0.rank && "CDHS".contains($0.suit)}) else{return "Нужны 9 разных допустимых карт."}
 var lines=["Ретроспектива против показанной руки (не оценка решения):"]
 for n in [3,4,5] { let prefix=Array(board.prefix(n)); let known=Set(hero+opponent+prefix); let deck=((short ? 6:2)...14).flatMap{r in Array("CDHS").map{Card(rank:r,suit:$0)}}.filter{!known.contains($0)}; var wins=0,ties=0,total=0
 func evaluate(_ tail:[Card]) {let a=best(hero+prefix+tail,short:short), b=best(opponent+prefix+tail,short:short); total+=1; if a==b{ties+=1}else if b.lexicographicallyPrecedes(a){wins+=1}}
 if n==5{evaluate([])}else if n==4{for c in deck{evaluate([c])}}else{for i in deck.indices{for j in deck.indices where j>i{evaluate([deck[i],deck[j]])}}}; lines.append("\([3:"Флоп",4:"Тёрн",5:"Ривер"][n]!): \(String(format:"%.1f",100*(Double(wins)+Double(ties)/2)/Double(total)))% equity (\(total) вариантов)")
 }; return lines.joined(separator:"\n")
}

// Portable diagnostics helpers. Do not guess the game from a number or an obscured caption.
func detectGameFormat(_ raw:String)->String {
 let lower=raw.lowercased()
 let omaha=lower.range(of:#"(?<![\p{L}])(?:омаха|omaha)(?![\p{L}])"#,options:.regularExpression) != nil
 let holdem=lower.range(of:#"(?<![\p{L}])(?:холдем|holdem|hold['’]em|техас|texas)(?![\p{L}])"#,options:.regularExpression) != nil
 guard omaha != holdem else{return "не определён"}
 if omaha {return "Омаха"}
 let short=lower.range(of:#"(?:6[ \t]*\+[ \t]*(?:холдем|holdem|hold['’]em|техас|texas)|(?:холдем|holdem|hold['’]em|техас|texas)[ \t]*6[ \t]*\+)"#,options:.regularExpression) != nil
 if !short && lower.range(of:#"(?<![\p{L}])(?:холдем|holdem|hold['’]em)(?![\p{L}])"#,options:.regularExpression) == nil {return "не определён"}
 return short ? "6+ Холдем" : "Холдем"
}
func hasActiveAction(_ lines:[String])->Bool {
 let active:Set<String>=["ставит","чек","колл","рейз","фолд","бет","думает","bet","check","call","raise","fold","thinking"]
 let punctuation=CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
 return lines.contains{active.contains($0.trimmingCharacters(in:punctuation).lowercased())}
}
func isReviewWindow(_ raw:String)->Bool {
 let lower=raw.lowercased()
 return lower.contains("установить zip") && (lower.contains("показать ocr") || lower.contains("журнал отчётов") || lower.contains("проверить обновления") || lower.contains("обновить из github"))
}
enum CardReadFailure: String, Codable {case notChecked, unreadableImage, unsupportedLayout, rankUnconfirmed, suitUnconfirmed, duplicateCards, invalidDeck, none}
func isSupportedCardLayout(width:Int,height:Int)->Bool {
 guard width>0,height>0 else{return false}
 return abs(Double(width)/Double(height)-1350.0/1120.0)<0.045
}
enum ReviewGate: String, Codable {
 case notChecked, activeAction, unknownFormat, unsupportedFormat, missingShowdownMarkers, cardsUnconfirmed, candidate, notTableImage, ambiguousShowdown
 static func assess(game:String, markers:Int, active:Bool, cardsRecognized:Bool)->ReviewGate {
  if active {return .activeAction}
  if game == "не определён" {return .unknownFormat}
  if game != "Холдем" && game != "6+ Холдем" {return .unsupportedFormat}
  if markers < 2 {return .missingShowdownMarkers}
  if markers != 2 {return .ambiguousShowdown}
  return cardsRecognized ? .candidate : .cardsUnconfirmed
 }
}
// Public payload: only closed enums, bounded counters and booleans. No input strings.
struct DiagnosticEvent: Codable {
 enum Status:String, Codable {case connected, completed, unconfirmed, recognitionError}
 let status:Status
 var stacks:Int=0
 var cards:Int=0
 var bank:Bool=false
 var payout:Bool=false
 var reason:ReviewGate = .notChecked
 var cardFailure:CardReadFailure? = nil
 var recordedVersion:String? = "2.9"
 var body:String {let version=recordedVersion.flatMap{SourceUpdateManifest.validVersion($0) ? $0:nil} ?? "unknown";return "review_version=\(version)\nstatus=\(status.rawValue)\nstacks=\(max(0,min(6,stacks)))\ncards=\(max(0,min(9,cards)))\nbank_detected=\(bank)\npayout_detected=\(payout)\nreason=\(reason.rawValue)\ncard_failure=\((cardFailure ?? .notChecked).rawValue)"}
}


// Persist only typed technical events, never credentials or OCR.
struct DiagnosticQueue {
 private(set) var events:[DiagnosticEvent]=[]
 let capacity:Int=100
 mutating func append(_ event:DiagnosticEvent)->Bool {guard events.count<capacity else{return false};events.append(event);return true}
 func batch()->[DiagnosticEvent] {Array(events.prefix(10))}
 mutating func acknowledge(_ count:Int){events.removeFirst(max(0,min(count,events.count)))}
 mutating func pop(){acknowledge(1)}
 mutating func clear(){events.removeAll()}
 static func restore(_ data:Data?)->DiagnosticQueue {
  var q=DiagnosticQueue();if let data=data,data.count<=100_000,let values=try? JSONDecoder().decode([DiagnosticEvent].self,from:data){q.events=Array(values.prefix(q.capacity))};return q
 }
}

// Fixed allowlist for the opt-in GitHub source update channel.
let updateSourceNames = ["main.swift", "Math.swift", "Cards.swift", "Templates.swift", "Update.swift"]
struct SourceUpdateManifest: Decodable {
 struct Entry: Decodable { let name:String; let sha256:String }
 let version:String; let base:String?; let commit:String?; let files:[Entry]
 static func validVersion(_ s:String)->Bool { s.range(of:"\\A[0-9]{1,4}\\.[0-9]{1,4}\\z",options:.regularExpression) != nil }
 func isNewer(than old:String)->Bool { Self.validVersion(version) && Self.validVersion(old) && version.compare(old,options:.numeric) == .orderedDescending }
 func validPatch(from old:String)->Bool {
  guard isNewer(than:old),base==old,let commit=commit,commit.range(of:"\\A[a-f0-9]{40}\\z",options:.regularExpression) != nil,!files.isEmpty,files.count<=updateSourceNames.count else{return false}
  return Set(files.map{$0.name}).count==files.count && files.contains{$0.name=="main.swift"} && files.allSatisfy{updateSourceNames.contains($0.name) && $0.sha256.range(of:"\\A[a-f0-9]{64}\\z",options:.regularExpression) != nil}
 }
}
func sourceVersion(_ source:String)->String? {
 guard let range=source.range(of:"Pokerdom Review [0-9]+\\.[0-9]+",options:.regularExpression) else{return nil}
 return String(source[range].dropFirst("Pokerdom Review ".count))
}

// For confirmed archived Omaha hands only: exactly two hole cards and three board cards.
func omahaScore(_ hole:[Card],_ board:[Card])->[Int]? {
 guard hole.count == 4, board.count == 5, Set(hole+board).count == 9, (hole+board).allSatisfy({(2...14).contains($0.rank) && "CDHS".contains($0.suit)}) else {return nil}
 var result=[-1]
 for i in 0..<4 {for j in (i+1)..<4 {for a in 0..<5 {for b in (a+1)..<5 {for c in (b+1)..<5 {
 let candidate=score5([hole[i],hole[j],board[a],board[b],board[c]],short:false)
 if result.lexicographicallyPrecedes(candidate){result=candidate}
 }}}}}
 return result
}
// Alternative calibrated stack centers for the tall tournament screenshot.
func tournamentStackCenters(_ raw:String)->[(Double,Double)]? {
 let lower=raw.lowercased()
 guard lower.range(of:#"(?<![\p{L}])(?:ребай|фриб[аa]й|rebuy|freeroll)(?![\p{L}])"#,options:.regularExpression) != nil else{return nil}
 return [(0.14,0.58),(0.50,0.71),(0.87,0.58),(0.12,0.17),(0.89,0.17),(0.50,0.03)]
}

// Only accept nearly uniform outer bands; do not stretch an arbitrary table.
func centeredCardCrop(width:Int,height:Int)->(Int,Int,Int,Int)? {
 guard width>0,height>0 else{return nil}
 let ratio=1350.0/1120.0
 if isSupportedCardLayout(width:width,height:height){return (0,0,width,height)}
 if Double(width)/Double(height)>ratio {
  let w=Int((Double(height)*ratio).rounded());let x=(width-w)/2
  guard x>0,w>0,Double(x)/Double(width)<=0.25 else{return nil};return (x,0,w,height)
 }
 let h=Int((Double(width)/ratio).rounded());let y=(height-h)/2
 guard y>0,h>0,Double(y)/Double(height)<=0.25 else{return nil};return (0,y,width,h)
}
func uniformPadding(_ samples:[Int])->Bool {
 guard samples.count>=12,let lo=samples.min(),let hi=samples.max() else{return false};return lo>=0 && hi<=255 && hi-lo<=8
}
func confirmedOmahaResult(_ a:[Card],_ b:[Card],_ board:[Card])->String? {
 guard Set(a+b+board).count==13,let x=omahaScore(a,board),let y=omahaScore(b,board) else{return nil}
 let names=["Старшая карта","Пара","Две пары","Тройка","Стрит","Флеш","Фулл-хаус","Каре","Стрит-флеш"]
 let winner=x==y ? "Равные комбинации" : (x.lexicographicallyPrecedes(y) ? "Вторая рука сильнее" : "Первая рука сильнее")
 return "Итог по введённым открытым картам: \(winner). Первая: \(names[x[0]]); вторая: \(names[y[0]]). Не учитывает неизвестные руки, побочные банки и выплаты."
}
func mayReviewArchivedOmaha(game:String,markers:Int,active:Bool)->Bool {game == "Омаха" && markers==2 && !active}
func acceptsFive(_ observations:[(String,Double)])->Bool {observations.count==2 && observations.allSatisfy{$0.0.trimmingCharacters(in:.whitespacesAndNewlines)=="5" && $0.1>=0.95}}

func validArchivedDeck(_ a:String,_ b:String,_ board:String,short:Bool)->Bool {
 guard let h=parseCards(a),let o=parseCards(b),let t=parseCards(board),h.count==2,o.count==2,t.count==5 else{return false};let all=h+o+t
 return Set(all).count==9 && all.allSatisfy{(short ? 6:2)...14 ~= $0.rank}
}

// Use distinct locations, not distinct text: two players may have identical results.
func isShowdownMarker(_ text:String)->Bool {
 let lower=text.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
 let label=lower.range(of:#"^(?:старшая карта|две пары|пара|тройка|сет|стрит[ -]?флеш|стрит|флеш|фулл[ -]?хаус|каре|роял[ -]?флеш|high card|two pair|pair|three of a kind|straight flush|straight|flush|full house|four of a kind|royal flush)(?=[\s,:;]|$)"#,options:.regularExpression) != nil
 // A result label must include a percentage, not just an avatar/name.
 return label && lower.range(of:#"(?:^|[^\d.,])(?:0|50|100)(?:[.,]0+)?\s*%\s*$"#,options:.regularExpression) != nil
}
func distinctShowdownMarkers(_ observations:[(String,Double,Double)])->[(String,Double,Double)] {
 var result=[(String,Double,Double)]()
 for item in observations where isShowdownMarker(item.0) {
  guard (0...1).contains(item.1),(0...1).contains(item.2) else{continue}
  if !result.contains(where:{abs($0.1-item.1)<0.06 && abs($0.2-item.2)<0.06}){result.append(item)}
 }
 return result
}
// Resolve off-centre constant-colour margins without stretching table content.
// The callback must verify all pixels sampled from each outer band.
func locateCardCrop(width:Int,height:Int,flat:(Int,Int,Int,Int)->Bool)->(Int,Int,Int,Int)? {
 guard let centered=centeredCardCrop(width:width,height:height) else{return nil}
 let (_,_,cw,ch)=centered
 let horizontal=cw<width, total=horizontal ? width-cw : height-ch
 if total==0{return centered}
 let dimension=horizontal ? width:height
 let cap=min(total,dimension/4)
 func band(_ leading:Bool,_ amount:Int)->Bool {
  if amount==0{return true}
  if horizontal {return flat(leading ? 0:width-amount,0,amount,height)}
  return flat(0,leading ? 0:height-amount,width,amount)
 }
 func largest(_ leading:Bool)->Int {
  var lo=0,hi=cap
  while lo<hi {let mid=(lo+hi+1)/2;if band(leading,mid){lo=mid}else{hi=mid-1}}
  return lo
 }
 let a=largest(true),b=largest(false)
 let lower=max(0,total-b),upper=min(total,a)
 // Ambiguous margins or any content in the stripped area are rejected.
 guard lower<=upper,upper-lower<=2 else{return nil}
 let leading=(lower+upper)/2
 guard band(true,leading),band(false,total-leading) else{return nil}
 return horizontal ? (leading,0,cw,ch):(0,leading,cw,ch)
}

// A two-hand archive must show complementary terminal percentages, not merely two labels.
func terminalShowdownPercent(_ text:String)->Int? {
 guard isShowdownMarker(text),let range=text.range(of:#"(?<![\d.,])(?:0|50|100)(?:[.,]0+)?\s*%\s*$"#,options:.regularExpression) else{return nil}
 let value=text[range].prefix(while:{$0.isNumber});return Int(value)
}
func hasConsistentShowdownPair(_ labels:[String])->Bool {
 guard labels.count==2,let a=terminalShowdownPercent(labels[0]),let b=terminalShowdownPercent(labels[1]) else{return false}
 return a+b==100
}
func preferTournamentStacks(regular:Int,alternate:Int)->Bool {
 (0...6).contains(regular) && (4...6).contains(alternate) && alternate>regular
}

// A fallback for a saved screenshot with complementary terminal labels only.
// It never converts unconfirmed or active play into a completed result.
func manualArchiveFormat(game:String,labels:[String],active:Bool)->String? {
 guard !active,hasConsistentShowdownPair(labels),["Холдем","6+ Холдем","Омаха"].contains(game) else{return nil}
 return game
}

// Whole-image OCR fallback for explicitly labelled tournaments. Only a unique
// integer line next to a seat name may fill a missing stack. Never use a chip
// amount in the centre of the table, an action label, or an ambiguous reading.
struct StackObservation {
 let text:String
 let x:Double
 let y:Double
 let confidence:Double
}
func tournamentInteger(_ raw:String)->String? {
 let text=raw.trimmingCharacters(in:.whitespacesAndNewlines)
 guard text.range(of:#"^(?:0|[1-9][0-9]*|[1-9][0-9]{0,2}(?:[ \u00a0\u202f][0-9]{3})+)$"#,options:.regularExpression) != nil else{return nil}
 let value=text.filter{!$0.isWhitespace}
 guard value.count<=12 else{return nil};return value
}
func tournamentStackFromObservations(_ observations:[StackObservation],x:Double,y:Double)->String? {
 let nearby=observations.filter{ $0.confidence>=0.85 && abs($0.x-x)<=0.075 && abs($0.y-y)<=0.055 }
 let candidates=nearby.compactMap { obs -> (StackObservation,String)? in
  guard let amount=tournamentInteger(obs.text) else{return nil}
  let names=observations.filter { name in
   let t=name.text.trimmingCharacters(in:.whitespacesAndNewlines), lower=t.lowercased()
   return name.confidence>=0.75 && abs(name.x-obs.x)<=0.045 && (0.014...0.055).contains(name.y-obs.y) && t.count>=2 && t.count<=32 && (t.contains(where:{$0.isLetter}) || t.allSatisfy{$0=="*"}) && !hasActiveAction([t]) && !["банк","pot","ребай","rebuy","freeroll","омаха","omaha","холдем","holdem","техас","texas"].contains(where:{lower.contains($0)}) && !t.contains("%")
  }
  guard names.count==1 else{return nil};return (obs,amount)
 }
 guard candidates.count==1 else{return nil};return candidates[0].1
}

// The existing template reader is calibrated for two specific positions.
// Do not attribute a result from different seats to these positions.
func calibratedShowdownSeats(_ markers:[(String,Double,Double)])->Bool {
 guard markers.count==2 else{return false}
 let upper=markers.filter{abs($0.1-0.145)<=0.09 && abs($0.2-0.697)<=0.07}
 let lower=markers.filter{abs($0.1-0.126)<=0.09 && abs($0.2-0.326)<=0.07}
 return upper.count==1 && lower.count==1
}

// Compare every expected field independently. A missing line never counts as a match.
func matchingFixtureLines(_ report:String,expected:[String])->Int {
 let lines=Set(report.components(separatedBy:"\n"))
 return expected.filter{lines.contains($0)}.count
}
