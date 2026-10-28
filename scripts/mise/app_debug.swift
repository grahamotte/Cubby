import Foundation

DistributedNotificationCenter.default().postNotificationName(Notification.Name("cubby.debug"), object: CommandLine.arguments[1], userInfo: nil, deliverImmediately: true)
