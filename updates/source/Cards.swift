import Cocoa
import CoreGraphics
import ImageIO
import Vision
import CoreImage
// Decode and crop once; OCR, stack coordinates and cards must use the same image.
func loadArchiveImage(_ url:URL)->CGImage? {
 guard let source=CGImageSourceCreateWithURL(url as CFURL,nil) else{return nil}
 return CGImageSourceCreateImageAtIndex(source,0,nil)
}
func cropArchiveImage(_ image:CGImage)->CGImage? {
 // Test every pixel in an outer band; shrinking to a thumbnail can hide table content.
 func flat(_ x:Int,_ y:Int,_ w:Int,_ h:Int)->Bool {
  guard w>0,h>0,w<=8192,h<=8192,w*h<=8_000_000,let margin=image.cropping(to:CGRect(x:x,y:y,width:w,height:h)),let sample=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return false}
  sample.interpolationQuality = .none; sample.draw(margin,in:CGRect(x:0,y:0,width:w,height:h))
  guard let raw=sample.data else{return false};let bytes=raw.assumingMemoryBound(to:UInt8.self)
  var low=[255,255,255],high=[0,0,0]
  for i in 0..<(w*h) {
   for c in 0..<3 {let v=Int(bytes[i*4+c]);low[c]=min(low[c],v);high[c]=max(high[c],v);if high[c]-low[c]>8{return false}}
  }
  return true
 }
 guard let (x,y,cw,ch)=locateCardCrop(width:image.width,height:image.height,flat:flat) else{return nil}
 var input=image
 if cw != image.width || ch != image.height {
  guard let cropped=image.cropping(to:CGRect(x:x,y:y,width:cw,height:ch)) else{return nil};input=cropped
 }
 return input
}
// Calibrated six-seat layout; unknown glyphs and ambiguous matches are rejected.
func recognizeArchivedCards(_ input: CGImage, failure: inout CardReadFailure) -> (String,String,String)? {
 failure = .unsupportedLayout
 guard isSupportedCardLayout(width:input.width,height:input.height) else{return nil}
 failure = .unreadableImage
 let w=1350,h=1120
 guard let ctx=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return nil}
 ctx.draw(input,in:CGRect(x:0,y:0,width:w,height:h)); guard let normalized=ctx.makeImage() else{return nil}
 func match(_ x:Int,_ y:Int,_ kind:String)->String? {
 let rect = kind == "rank" ? CGRect(x:x+4,y:y+3,width:38,height:44) : CGRect(x:x+4,y:y+54,width:32,height:33)
 guard let crop=normalized.cropping(to:rect),let small=CGContext(data:nil,width:24,height:24,bitsPerComponent:8,bytesPerRow:96,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return nil}
 small.draw(crop,in:CGRect(x:0,y:0,width:24,height:24)); guard let data=small.data else{return nil}; let bytes=data.assumingMemoryBound(to:UInt8.self)
 let values=(0..<576).map { i in Int(min(bytes[i*4],min(bytes[i*4+1],bytes[i*4+2]))) }; let bg=values.sorted()[489]; guard bg>65 else{return nil}
 let mask=values.map{Double($0)<Double(bg)*0.72}; let count=mask.filter{$0}.count; guard count>20,count<440 else{return nil}
 var scores=[String:Double]()
 for (type,label,bits) in templates where type==kind {let d=Double(zip(mask,bits).filter{$0.0 != ($0.1 == "1")}.count)/576; scores[label]=min(scores[label] ?? 1,d)}
 let ordered=scores.sorted{$0.value<$1.value}
 if ordered.count>1,ordered[0].value<0.15,ordered[1].value-ordered[0].value>0.025 {return ordered[0].key}
 // Only the missing rank 5, and only if two independent preprocessing passes agree.
 guard kind == "rank" else{return nil}
 let ci=CIImage(cgImage:crop), context=CIContext(options:nil)
 let variants=[ci,ci.applyingFilter("CIColorControls",parameters:[kCIInputSaturationKey:0,kCIInputContrastKey:1.5])]
 var observations=[(String,Double)]()
 for variant in variants {
  let scaled=variant.transformed(by:CGAffineTransform(scaleX:4,y:4))
  guard let cg=context.createCGImage(scaled,from:scaled.extent) else{return nil}
  let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.recognitionLanguages=["en-US"];request.usesLanguageCorrection=false
  guard (try? VNImageRequestHandler(cgImage:cg,options:[:]).perform([request])) != nil,let results=request.results,results.count==1,let candidate=results[0].topCandidates(1).first else{return nil}
  observations.append((candidate.string,Double(candidate.confidence)))
 }
 return acceptsFive(observations) ? "5" : nil
 }
 func cards(_ points:[(Int,Int)])->String? {var result=[String]();for (x,y) in points {guard let r=match(x,y,"rank") else{failure = .rankUnconfirmed;return nil};guard let s=match(x,y,"suit") else{failure = .suitUnconfirmed;return nil};result.append(r+s)};return result.joined(separator:" ")}
 if let a=cards([(71,626),(171,626)]),let b=cards([(97,223),(197,223)]),let board=cards([(431,450),(531,450),(631,450),(731,464),(831,464)]) {guard let all=parseCards(a+" "+b+" "+board),Set(all).count==9 else{failure = .duplicateCards;return nil};failure = .none;return (a,b,board)}
 return nil
}
