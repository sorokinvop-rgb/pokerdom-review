import Cocoa
import CoreGraphics
import ImageIO
// Calibrated six-seat layout; unknown glyphs and ambiguous matches are rejected.
func recognizeArchivedCards(_ url: URL, failure: inout CardReadFailure) -> (String,String,String)? {
 failure = .unreadableImage
 guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else{return nil}
 let w=1350,h=1120
 guard isSupportedCardLayout(width:image.width,height:image.height) else{failure = .unsupportedLayout;return nil}
 guard let ctx=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return nil}
 ctx.draw(image,in:CGRect(x:0,y:0,width:w,height:h)); guard let normalized=ctx.makeImage() else{return nil}
 func match(_ x:Int,_ y:Int,_ kind:String)->String? {
 let rect = kind == "rank" ? CGRect(x:x+4,y:y+3,width:38,height:44) : CGRect(x:x+4,y:y+54,width:32,height:33)
 guard let crop=normalized.cropping(to:rect),let small=CGContext(data:nil,width:24,height:24,bitsPerComponent:8,bytesPerRow:96,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return nil}
 small.draw(crop,in:CGRect(x:0,y:0,width:24,height:24)); guard let data=small.data else{return nil}; let bytes=data.assumingMemoryBound(to:UInt8.self)
 let values=(0..<576).map { i in Int(min(bytes[i*4],min(bytes[i*4+1],bytes[i*4+2]))) }; let bg=values.sorted()[489]; guard bg>65 else{return nil}
 let mask=values.map{Double($0)<Double(bg)*0.72}; let count=mask.filter{$0}.count; guard count>20,count<440 else{return nil}
 var scores=[String:Double]()
 for (type,label,bits) in templates where type==kind {let d=Double(zip(mask,bits).filter{$0.0 != ($0.1 == "1")}.count)/576; scores[label]=min(scores[label] ?? 1,d)}
 let ordered=scores.sorted{$0.value<$1.value}; guard ordered.count>1,ordered[0].value<0.15,ordered[1].value-ordered[0].value>0.025 else{return nil}; return ordered[0].key
 }
 func cards(_ points:[(Int,Int)])->String? {var result=[String]();for (x,y) in points {guard let r=match(x,y,"rank") else{failure = .rankUnconfirmed;return nil};guard let s=match(x,y,"suit") else{failure = .suitUnconfirmed;return nil};result.append(r+s)};return result.joined(separator:" ")}
 if let a=cards([(71,626),(171,626)]),let b=cards([(97,223),(197,223)]),let board=cards([(431,450),(531,450),(631,450),(731,464),(831,464)]) {guard let all=parseCards(a+" "+b+" "+board),Set(all).count==9 else{failure = .duplicateCards;return nil};failure = .none;return (a,b,board)}
 return nil
}
