import Foundation
struct Card: Hashable { let rank:Int; let suit:Character }
func parseCards(_ s:String)->[Card]? {
 let ranks=Array("23456789TJQKA"); var result=[Card]()
 for token in s.uppercased().split(whereSeparator:{$0.isWhitespace || $0 == ","}) {
 let a=Array(token.replacingOccurrences(of:"10",with:"T")); guard a.count==2, let r=ranks.firstIndex(of:a[0]), "CDHS".contains(a[1]) else{return nil}; result.append(Card(rank:r+2,suit:a[1]))
 }; return result
}
func score5(_ cards:[Card],short:Bool)->[Int] {
 let r=cards.map{$0.rank}.sorted(by:>); let grouped = Dictionary(grouping:r,by:{$0}); let counts:[(Int,Int)] = grouped.map { ($0.key,$0.value.count) }; let groups = counts.sorted { a,b in if a.1 == b.1 { return a.0 > b.0 }; return a.1 > b.1 }; let flush=Set(cards.map{$0.suit}).count==1
 let straight=Set(r).count==5 ? (r[0]-r[4]==4 ? r[0] : (r == (short ? [14,9,8,7,6] : [14,5,4,3,2]) ? (short ? 9:5):0)):0
 if flush && straight>0{return [8,straight]}; if groups[0].1==4{return [7,groups[0].0,groups[1].0]}; if groups[0].1==3 && groups[1].1==2{return [short ? 5:6,groups[0].0,groups[1].0]}; if flush{return [short ? 6:5]+r}; if straight>0{return [4,straight]}; if groups[0].1==3{return [3]+groups.map{$0.0}}; if groups[0].1==2 && groups[1].1==2{return [2]+groups.map{$0.0}}; if groups[0].1==2{return [1]+groups.map{$0.0}}; return [0]+r
}
func best(_ cards:[Card],short:Bool)->[Int] { var b=[-1]; for i in 0..<cards.count { for j in (i+1)..<cards.count { let s=score5(cards.enumerated().filter{$0.offset != i && $0.offset != j}.map{$0.element},short:short); if b.lexicographicallyPrecedes(s){b=s} } }; return b }
func retrospective(_ hero:[Card],_ opponent:[Card],_ board:[Card],short:Bool)->String {
 let all=hero+opponent+board; guard hero.count==2,opponent.count==2,board.count==5,Set(all).count==9,all.allSatisfy({$0.rank >= (short ? 6:2)}) else{return "Нужны 9 разных допустимых карт."}
 var lines=["Ретроспектива против показанной руки (не оценка решения):"]
 for n in [3,4,5] { let prefix=Array(board.prefix(n)); let known=Set(hero+opponent+prefix); let deck=((short ? 6:2)...14).flatMap{r in Array("CDHS").map{Card(rank:r,suit:$0)}}.filter{!known.contains($0)}; var wins=0,ties=0,total=0
 func evaluate(_ tail:[Card]) {let a=best(hero+prefix+tail,short:short), b=best(opponent+prefix+tail,short:short); total+=1; if a==b{ties+=1}else if b.lexicographicallyPrecedes(a){wins+=1}}
 if n==5{evaluate([])}else if n==4{for c in deck{evaluate([c])}}else{for i in deck.indices{for j in deck.indices where j>i{evaluate([deck[i],deck[j]])}}}; lines.append("\([3:"Флоп",4:"Тёрн",5:"Ривер"][n]!): \(String(format:"%.1f",100*(Double(wins)+Double(ties)/2)/Double(total)))% equity (\(total) вариантов)")
 }; return lines.joined(separator:"\n")
}

// Portable diagnostics helpers. Do not guess the game from a number or an obscured caption.
func detectGameFormat(_ raw:String)->String {
 let lower=raw.lowercased()
 if lower.contains("омаха") || lower.contains("omaha") {return "Омаха"}
 if lower.contains("холдем") || lower.contains("holdem") || lower.contains("hold'em") {return lower.contains("6+") ? "6+ Холдем" : "Холдем"}
 return "не определён"
}
func hasActiveAction(_ lines:[String])->Bool {
 let active:Set<String>=["ставит","чек","колл","рейз","bet","check","call","raise"]
 return lines.contains{active.contains($0.trimmingCharacters(in:.whitespacesAndNewlines).lowercased())}
}
// Public payload: only closed enums, bounded counters and booleans. No input strings.
struct DiagnosticEvent {
 enum Status:String {case connected, completed, unconfirmed, recognitionError}
 let status:Status
 var stacks:Int=0
 var cards:Int=0
 var bank:Bool=false
 var payout:Bool=false
 var body:String {"review_version=2.5\nstatus=\(status.rawValue)\nstacks=\(max(0,min(6,stacks)))\ncards=\(max(0,min(9,cards)))\nbank_detected=\(bank)\npayout_detected=\(payout)"}
}


// Fixed allowlist for the opt-in GitHub source update channel.
let updateSourceNames = ["main.swift", "Math.swift", "Cards.swift", "Templates.swift", "Update.swift"]
struct SourceUpdateManifest: Decodable {
 struct Entry: Decodable { let name:String; let sha256:String }
 let version:String; let base:String?; let commit:String?; let files:[Entry]
 static func validVersion(_ s:String)->Bool { s.range(of:"^[0-9]{1,4}\\.[0-9]{1,4}$",options:.regularExpression) != nil }
 func isNewer(than old:String)->Bool { Self.validVersion(version) && Self.validVersion(old) && version.compare(old,options:.numeric) == .orderedDescending }
 func validPatch(from old:String)->Bool {
  guard isNewer(than:old),base==old,let commit=commit,commit.range(of:"^[a-f0-9]{40}$",options:.regularExpression) != nil,!files.isEmpty,files.count<=updateSourceNames.count else{return false}
  return Set(files.map{$0.name}).count==files.count && files.contains{$0.name=="main.swift"} && files.allSatisfy{updateSourceNames.contains($0.name) && $0.sha256.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil}
 }
}
func sourceVersion(_ source:String)->String? {
 guard let range=source.range(of:"Pokerdom Review [0-9]+\\.[0-9]+",options:.regularExpression) else{return nil}
 return String(source[range].dropFirst("Pokerdom Review ".count))
}
