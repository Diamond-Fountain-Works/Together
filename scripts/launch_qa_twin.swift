import AppKit
import Foundation

// Shell-launched QA only. LaunchServices starts the verified GUI bundle.
let args = CommandLine.arguments
guard args.count == 3, let bytes = FileManager.default.contents(atPath: args[1]),
      let rows = try JSONSerialization.jsonObject(with: bytes) as? [[String:String]],
      let row = rows.first(where: {$0["label"] == args[2]}), let path=row["bundle"], let root=row["root"], let origin=row["origin"],
      let url=URL(string:origin), url.scheme=="http", url.host=="127.0.0.1", url.port != nil,
      let info=NSDictionary(contentsOfFile:path+"/Contents/Info.plist"),
      info["CFBundleIdentifier"] as? String == "com.together.app.qa."+args[2],
      URL(fileURLWithPath:root).lastPathComponent.hasPrefix("together-ui-twins-") else {fatalError("Verified isolated QA configuration required")}
let configuration=NSWorkspace.OpenConfiguration()
configuration.createsNewApplicationInstance=true
configuration.arguments=["--ui-testing","-AppleLanguages","(zh-Hans)","-AppleLocale","zh_CN"]
configuration.environment=["TOGETHER_UI_PAGE":"partner-pairing","TOGETHER_UI_ROOT":root,"TOGETHER_UI_STATE":"empty","TOGETHER_UI_MODE":"light","TOGETHER_UI_RELAY_URL":origin,"TOGETHER_UI_REDUCE_MOTION":"1"]
NSWorkspace.shared.openApplication(at:URL(fileURLWithPath:path),configuration:configuration){app,error in
    if let error {fputs(error.localizedDescription+"\n",stderr);exit(1)}
    guard let app, app.bundleIdentifier == row["bundleID"] else {exit(1)}
    print("QA "+args[2]+" pid="+String(app.processIdentifier));exit(0)
}
RunLoop.main.run()
