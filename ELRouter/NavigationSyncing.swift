//
//  NavigationSyncing.swift
//  ELRouter
//
//  Created by Brandon Sneed on 10/15/15.
//  Copyright © 2015 Walmart. All rights reserved.
//

/* 

TODO:

Consider getting rid of this file.  It's only needed to sync manual navigation events
with to prevent collison with router based nav events.  Do we need to do this?

If not, we just need to uncomment the swizzle in Router.swift.

*/

import Foundation
import UIKit
import ELFoundation
import ELDispatch

typealias NavSyncAction = () -> Void

public protocol RouterEventFirehose: class {
    func viewControllerAppeared(viewController: UIViewController)
    func viewControllerPresented(viewController: UIViewController)
    func viewControllerPushed(viewController: UIViewController)
}

internal class NavSync: NSObject {
    internal static var sharedInstance = NavSync()

    internal var scheduledControllers = NSHashTable.weakObjectsHashTable()
    
    let routerQueue: DispatchQueue
    weak var eventFirehose: RouterEventFirehose?
    
    override init() {
        routerQueue = DispatchQueue.createSerial("ELRouterSync", targetQueue: .Background)
        super.init()
    }
    
    internal func appeared(controller: UIViewController, animated: Bool) {
        eventFirehose?.viewControllerAppeared(controller)
        
        controller.swizzled_viewDidAppear(animated)
        Router.lock.unlock()
    }
    
    internal func push(viewController: UIViewController, animated: Bool, navController: UINavigationController, fromRouter: Bool) {
        // add it to the scheduled ones in the case of a double-show to prevent a system blow up.
        if scheduledControllers.containsObject(viewController) {
            return
        } else {
            scheduledControllers.addObject(viewController)
        }
        
        eventFirehose?.viewControllerPushed(viewController)
        
        // if routes are in process and a manual nav event was attempted, it's ignore it and continue on.
        if !fromRouter && Router.sharedInstance.processing {
            exceptionFailure("Attempted to push a ViewController while routes were being processed!")
            return
        }
        
        if animated {
            Dispatch().async(routerQueue) {
                Dispatch().async(.Main) {
                    navController.swizzled_pushViewController(viewController, animated: animated)
                    self.scheduledControllers.removeObject(viewController)
                }
            }
        } else {
            navController.swizzled_pushViewController(viewController, animated: animated)
            scheduledControllers.removeObject(viewController)
        }
    }

    internal func present(viewController: UIViewController, animated: Bool, completion: (() -> Void)?, fromController: UIViewController, fromRouter: Bool) {
        // add it to the scheduled ones in the case of a double-show to prevent a system blow up.
        if scheduledControllers.containsObject(viewController) {
            return
        } else {
            scheduledControllers.addObject(viewController)
        }
        
        eventFirehose?.viewControllerPresented(viewController)

        // if routes are in process and a manual nav event was attempted, it's ignore it and continue on.
        if !fromRouter && Router.sharedInstance.processing {
            exceptionFailure("Attempted to present a ViewController while routes were being processed!")
            return
        }
        
        if animated {
            Dispatch().async(routerQueue) {
                Dispatch().async(.Main) {
                    fromController.swizzled_presentViewController(viewController, animated: animated, completion: completion)
                    self.scheduledControllers.removeObject(viewController)
                }
            }
        } else {
            fromController.swizzled_presentViewController(viewController, animated: animated, completion: completion)
            scheduledControllers.removeObject(viewController)
        }
    }
    
    internal func performSegueWithIdentifier(identifier: String, sender: AnyObject?, fromController: UIViewController, fromRouter: Bool) {
        // if routes are in process and a manual nav event was attempted, it's ignore it and continue on.
        if !fromRouter && Router.sharedInstance.processing {
            exceptionFailure("Attempted to perform a segue while routes were being processed!")
            return
        }

        fromController.performSegueWithIdentifier(identifier, sender: sender)
    }
}

extension UINavigationController {
    public override class func initialize() {
        struct Static {
            static var token: dispatch_once_t = 0
        }
        
        // make sure this isn't a subclass
        if self !== UINavigationController.self {
            return
        }
        
        dispatch_once(&Static.token) {
            unsafeSwizzle(self, original: #selector(UINavigationController.pushViewController(_:animated:)), replacement: #selector(UINavigationController.swizzled_pushViewController(_:animated:)))
            
            // TODO: figure out if we need to handle popViewController, popToRootViewController and popToViewController.
        }
    }
    
    // MARK: - Method Swizzling
    
    internal func swizzled_pushViewController(viewController: UIViewController, animated: Bool) {
        NavSync.sharedInstance.push(viewController, animated: animated, navController: self, fromRouter: false)
    }

    internal func router_pushViewController(viewController: UIViewController, animated: Bool) {
        NavSync.sharedInstance.push(viewController, animated: animated, navController: self, fromRouter: true)
    }
}

extension UIViewController {
    public override class func initialize() {
        struct Static {
            static var token: dispatch_once_t = 0
        }
        
        // make sure this isn't a subclass
        if self !== UIViewController.self {
            return
        }
        
        dispatch_once(&Static.token) {
            unsafeSwizzle(self, original: #selector(UIViewController.viewDidAppear(_:)), replacement: #selector(UIViewController.swizzled_viewDidAppear(_:)))
            unsafeSwizzle(self, original: #selector(UIViewController.presentViewController(_:animated:completion:)), replacement: #selector(UIViewController.swizzled_presentViewController(_:animated:completion:)))
            
            // TODO: figure out if we need to handle dismissViewControllerAnimated
        }
    }
    
    // MARK: - Method Swizzling
    
    internal func swizzled_viewDidAppear(animated: Bool) {
        // release whatever lock is present
        NavSync.sharedInstance.appeared(self, animated: animated)
    }
    
    internal func swizzled_presentViewController(viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)?) {
        NavSync.sharedInstance.present(viewControllerToPresent, animated: animated, completion: completion, fromController: self, fromRouter: false)
    }
    
    internal func router_presentViewController(viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)?) {
        NavSync.sharedInstance.present(viewControllerToPresent, animated: animated, completion: completion, fromController: self, fromRouter: true)
    }
    
    internal func router_performSegueWithIdentifier(identifier: String, sender: AnyObject?) {
        NavSync.sharedInstance.performSegueWithIdentifier(identifier, sender: sender, fromController: self, fromRouter: true)
    }
}
