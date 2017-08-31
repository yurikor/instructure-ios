//
//  Toast.swift
//  Toast-Swift
//
//  Copyright (c) 2017 Charles Scalesse.
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the
//  "Software"), to deal in the Software without restriction, including
//  without limitation the rights to use, copy, modify, merge, publish,
//  distribute, sublicense, and/or sell copies of the Software, and to
//  permit persons to whom the Software is furnished to do so, subject to
//  the following conditions:
//
//  The above copyright notice and this permission notice shall be included
//  in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
//  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
//  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
//  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
//  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
import UIKit
import ObjectiveC

/**
 Toast is a Swift extension that adds toast notifications to the `UIView` object class.
 It is intended to be simple, lightweight, and easy to use. Most toast notifications
 can be triggered with a single line of code.
 
 The `makeToast` methods create a new view and then display it as toast.
 
 The `showToast` methods display any view as toast.
 
 */
public extension UIView {
    
    /**
     Keys used for associated objects.
     */
    private struct ToastKeys {
        static var timer        = "com.toast-swift.timer"
        static var duration     = "com.toast-swift.duration"
        static var point        = "com.toast-swift.point"
        static var completion   = "com.toast-swift.completion"
        static var activeToast  = "com.toast-swift.activeToast"
        static var activityView = "com.toast-swift.activityView"
        static var queue        = "com.toast-swift.queue"
    }
    
    /**
     Swift closures can't be directly associated with objects via the
     Objective-C runtime, so the (ugly) solution is to wrap them in a
     class that can be used with associated objects.
     */
    private class ToastCompletionWrapper {
        var completion: ((Bool) -> Void)?
        
        init(_ completion: ((Bool) -> Void)?) {
            self.completion = completion
        }
    }
    
    private enum ToastError: Error {
        case insufficientData
    }
    
    private var queue: NSMutableArray {
        get {
            if let queue = objc_getAssociatedObject(self, &ToastKeys.queue) as? NSMutableArray {
                return queue
            } else {
                let queue = NSMutableArray()
                objc_setAssociatedObject(self, &ToastKeys.queue, queue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                return queue
            }
        }
    }
    
    // MARK: - Make Toast Methods
    
    /**
     Creates and presents a new toast view.
     
     @param message The message to be displayed
     @param duration The toast duration
     @param position The toast's position
     @param title The title
     @param image The image
     @param style The style. The shared style will be used when nil
     @param completion The completion closure, executed after the toast view disappears.
     didTap will be `true` if the toast view was dismissed from a tap.
     */
    public func makeToast(_ message: String?, duration: TimeInterval = ToastManager.shared.duration, position: ToastPosition = ToastManager.shared.position, title: String? = nil, image: UIImage? = nil, style: ToastStyle = ToastManager.shared.style, completion: ((_ didTap: Bool) -> Void)? = nil) {
        do {
            let toast = try toastViewForMessage(message, title: title, image: image, style: style)
            showToast(toast, duration: duration, position: position, completion: completion)
        } catch ToastError.insufficientData {
            print("Error: message, title, and image are all nil")
        } catch {}
    }
    
    /**
     Creates a new toast view and presents it at a given center point.
     
     @param message The message to be displayed
     @param duration The toast duration
     @param point The toast's center point
     @param title The title
     @param image The image
     @param style The style. The shared style will be used when nil
     @param completion The completion closure, executed after the toast view disappears.
     didTap will be `true` if the toast view was dismissed from a tap.
     */
    public func makeToast(_ message: String?, duration: TimeInterval = ToastManager.shared.duration, point: CGPoint, title: String?, image: UIImage?, style: ToastStyle = ToastManager.shared.style, completion: ((_ didTap: Bool) -> Void)?) {
        do {
            let toast = try toastViewForMessage(message, title: title, image: image, style: style)
            showToast(toast, duration: duration, point: point, completion: completion)
        } catch ToastError.insufficientData {
            print("Error: message, title, and image cannot all be nil")
        } catch {}
    }
    
    // MARK: - Show Toast Methods
    
    /**
     Displays any view as toast at a provided position and duration. The completion closure
     executes when the toast view completes. `didTap` will be `true` if the toast view was
     dismissed from a tap.
     
     @param toast The view to be displayed as toast
     @param duration The notification duration
     @param position The toast's position
     @param completion The completion block, executed after the toast view disappears.
     didTap will be `true` if the toast view was dismissed from a tap.
     */
    public func showToast(_ toast: UIView, duration: TimeInterval = ToastManager.shared.duration, position: ToastPosition = ToastManager.shared.position, completion: ((_ didTap: Bool) -> Void)? = nil) {
        let point = position.centerPoint(forToast: toast, inSuperview: self)
        showToast(toast, duration: duration, point: point, completion: completion)
    }
    
    /**
     Displays any view as toast at a provided center point and duration. The completion closure
     executes when the toast view completes. `didTap` will be `true` if the toast view was
     dismissed from a tap.
     
     @param toast The view to be displayed as toast
     @param duration The notification duration
     @param point The toast's center point
     @param completion The completion block, executed after the toast view disappears.
     didTap will be `true` if the toast view was dismissed from a tap.
     */
    public func showToast(_ toast: UIView, duration: TimeInterval = ToastManager.shared.duration, point: CGPoint, completion: ((_ didTap: Bool) -> Void)? = nil) {
        objc_setAssociatedObject(toast, &ToastKeys.completion, ToastCompletionWrapper(completion), .OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        if let _ = objc_getAssociatedObject(self, &ToastKeys.activeToast) as? UIView, ToastManager.shared.isQueueEnabled {
            objc_setAssociatedObject(toast, &ToastKeys.duration, NSNumber(value: duration), .OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(toast, &ToastKeys.point, NSValue(cgPoint: point), .OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            
            queue.add(toast)
        } else {
            showToast(toast, duration: duration, point: point)
        }
    }
    
    // MARK: - Hide Toast Methods
    
    /**
     Hides all toast views and clears the queue.
     
     // @TODO: FIXME: this doesn't work then there's more than 1 active toast in the view
     
     */
    public func hideAllToasts() {
        queue.removeAllObjects()
        
        if let activeToast = objc_getAssociatedObject(self, &ToastKeys.activeToast) as? UIView {
            hideToast(activeToast)
        }
    }
    
    // MARK: - Activity Methods
    
    /**
     Creates and displays a new toast activity indicator view at a specified position.
     
     @warning Only one toast activity indicator view can be presented per superview. Subsequent
     calls to `makeToastActivity(position:)` will be ignored until `hideToastActivity()` is called.
     
     @warning `makeToastActivity(position:)` works independently of the `showToast` methods. Toast
     activity views can be presented and dismissed while toast views are being displayed.
     `makeToastActivity(position:)` has no effect on the queueing behavior of the `showToast` methods.
     
     @param position The toast's position
     */
    public func makeToastActivity(_ position: ToastPosition) {
        // sanity
        guard let _ = objc_getAssociatedObject(self, &ToastKeys.activityView) as? UIView else { return }
        
        let toast = createToastActivityView()
        let point = position.centerPoint(forToast: toast, inSuperview: self)
        makeToastActivity(toast, point: point)
    }
    
    /**
     Creates and displays a new toast activity indicator view at a specified position.
     
     @warning Only one toast activity indicator view can be presented per superview. Subsequent
     calls to `makeToastActivity(position:)` will be ignored until `hideToastActivity()` is called.
     
     @warning `makeToastActivity(position:)` works independently of the `showToast` methods. Toast
     activity views can be presented and dismissed while toast views are being displayed.
     `makeToastActivity(position:)` has no effect on the queueing behavior of the `showToast` methods.
     
     @param point The toast's center point
     */
    public func makeToastActivity(_ point: CGPoint) {
        // sanity
        guard let _ = objc_getAssociatedObject(self, &ToastKeys.activityView) as? UIView else { return }
        
        let toast = createToastActivityView()
        makeToastActivity(toast, point: point)
    }
    
    /**
     Dismisses the active toast activity indicator view.
     */
    public func hideToastActivity() {
        if let toast = objc_getAssociatedObject(self, &ToastKeys.activityView) as? UIView {
            UIView.animate(withDuration: ToastManager.shared.style.fadeDuration, delay: 0.0, options: [.curveEaseIn, .beginFromCurrentState], animations: {
                toast.alpha = 0.0
            }) { _ in
                toast.removeFromSuperview()
                objc_setAssociatedObject(self, &ToastKeys.activityView, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
    }
    
    // MARK: - Private Activity Methods
    
    private func makeToastActivity(_ toast: UIView, point: CGPoint) {
        toast.alpha = 0.0
        toast.center = point
        
        objc_setAssociatedObject(self, &ToastKeys.activityView, toast, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        self.addSubview(toast)
        
        UIView.animate(withDuration: ToastManager.shared.style.fadeDuration, delay: 0.0, options: .curveEaseOut, animations: {
            toast.alpha = 1.0
        })
    }
    
    private func createToastActivityView() -> UIView {
        let style = ToastManager.shared.style
        
        let activityView = UIView(frame: CGRect(x: 0.0, y: 0.0, width: style.activitySize.width, height: style.activitySize.height))
        activityView.backgroundColor = style.backgroundColor
        activityView.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
        activityView.layer.cornerRadius = style.cornerRadius
        
        if style.displayShadow {
            activityView.layer.shadowColor = style.shadowColor.cgColor
            activityView.layer.shadowOpacity = style.shadowOpacity
            activityView.layer.shadowRadius = style.shadowRadius
            activityView.layer.shadowOffset = style.shadowOffset
        }
        
        let activityIndicatorView = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
        activityIndicatorView.center = CGPoint(x: activityView.bounds.size.width / 2.0, y: activityView.bounds.size.height / 2.0)
        activityView.addSubview(activityIndicatorView)
        activityIndicatorView.startAnimating()
        
        return activityView
    }
    
    // MARK: - Private Show/Hide Methods
    
    private func showToast(_ toast: UIView, duration: TimeInterval, point: CGPoint) {
        toast.center = point
        
        var position = ToastManager.shared.position
        if (point.y == ToastPosition.center.centerPoint(forToast: toast, inSuperview: self).y) {
            toast.alpha = 0
            position = .center
        } else {
            toast.alpha = 1
            if (point.y == ToastPosition.top.centerPoint(forToast: toast, inSuperview: self).y) {
                position = .top
            } else {
                position = .bottom
            }
        }
        
        if ToastManager.shared.isTapToDismissEnabled {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(UIView.handleToastTapped(_:)))
            toast.addGestureRecognizer(recognizer)
            toast.isUserInteractionEnabled = true
            toast.isExclusiveTouch = true
        }
        
        objc_setAssociatedObject(self, &ToastKeys.activeToast, toast, .OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        self.addSubview(toast)
        
        UIView.animate(withDuration: ToastManager.shared.style.fadeDuration, delay: 0.0, options: [.curveEaseOut, .allowUserInteraction], animations: {
            switch position {
                case .top: toast.frame = CGRect(x: toast.frame.minX, y: toast.frame.minY + (toast.frame.height + ToastManager.shared.style.verticalPadding), width: toast.frame.width, height: toast.frame.height)
                    break
                case .center: toast.alpha = 1
                    break
                case .bottom: toast.frame = CGRect(x: toast.frame.minX, y: toast.frame.minY - (toast.frame.height + ToastManager.shared.style.verticalPadding), width: toast.frame.width, height: toast.frame.height)
                    break
            }
        }) { _ in
            let timer = Timer(timeInterval: duration, target: self, selector: #selector(UIView.toastTimerDidFinish(_:)), userInfo: toast, repeats: false)
            RunLoop.main.add(timer, forMode: RunLoopMode.commonModes)
            objc_setAssociatedObject(toast, &ToastKeys.timer, timer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    private func hideToast(_ toast: UIView) {
        hideToast(toast, fromTap: false)
    }
    
    private func hideToast(_ toast: UIView, fromTap: Bool) {
        
        var position = ToastManager.shared.position
        if (toast.center.y == ToastPosition.center.centerPoint(forToast: toast, inSuperview: self).y) {
            position = .center
        } else {
            if (toast.center.y < ToastPosition.center.centerPoint(forToast: toast, inSuperview: self).y) {
                position = .top
            } else {
                position = .bottom
            }
        }
        
        
        UIView.animate(withDuration: ToastManager.shared.style.fadeDuration, delay: 0.0, options: [.curveEaseIn, .beginFromCurrentState], animations: {
            switch position {
                case .top: toast.frame = CGRect(x: toast.frame.minX, y: toast.frame.minY - (toast.frame.height + ToastManager.shared.style.verticalPadding), width: toast.frame.width, height: toast.frame.height)
                    break
                case .center: toast.alpha = 0
                    break
                case .bottom: toast.frame = CGRect(x: toast.frame.minX, y: toast.frame.minY + (toast.frame.height + ToastManager.shared.style.verticalPadding), width: toast.frame.width, height: toast.frame.height)
                    break
            }
        }) { _ in
            toast.removeFromSuperview()
            
            objc_setAssociatedObject(self, &ToastKeys.activeToast, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            
            if let wrapper = objc_getAssociatedObject(toast, &ToastKeys.completion) as? ToastCompletionWrapper, let completion = wrapper.completion {
                completion(fromTap)
            }
            
            if let nextToast = self.queue.firstObject as? UIView, let duration = objc_getAssociatedObject(nextToast, &ToastKeys.duration) as? NSNumber, let point = objc_getAssociatedObject(nextToast, &ToastKeys.point) as? NSValue {
                self.queue.removeObject(at: 0)
                self.showToast(nextToast, duration: duration.doubleValue, point: point.cgPointValue)
            }
        }
    }
    
    // MARK: - Events
    
    func handleToastTapped(_ recognizer: UITapGestureRecognizer) {
        guard let toast = recognizer.view, let timer = objc_getAssociatedObject(toast, &ToastKeys.timer) as? Timer else { return }
        timer.invalidate()
        hideToast(toast, fromTap: true)
    }
    
    func toastTimerDidFinish(_ timer: Timer) {
        guard let toast = timer.userInfo as? UIView else { return }
        hideToast(toast)
    }
    
    // MARK: - Toast Construction
    
    /**
     Creates a new toast view with any combination of message, title, and image.
     The look and feel is configured via the style. Unlike the `makeToast` methods,
     this method does not present the toast view automatically. One of the `showToast`
     methods must be used to present the resulting view.
     
     @warning if message, title, and image are all nil, this method will throw
     `ToastError.InsufficientData`
     
     @param message The message to be displayed
     @param title The title
     @param image The image
     @param style The style. The shared style will be used when nil
     @throws `ToastError.InsufficientData` when message, title, and image are all nil
     @return The newly created toast view
     */
    public func toastViewForMessage(_ message: String?, title: String?, image: UIImage?, style: ToastStyle) throws -> UIView {
        // sanity
        guard message != nil || title != nil || image != nil else {
            throw ToastError.insufficientData
        }
        
        var messageLabel: UILabel?
        var titleLabel: UILabel?
        var imageView: UIImageView?
        
        let wrapperView = UIView()
        wrapperView.backgroundColor = style.backgroundColor
        wrapperView.layer.cornerRadius = style.cornerRadius
        
        if style.displayShadow {
            wrapperView.layer.shadowColor = style.shadowColor.cgColor
            wrapperView.layer.shadowOpacity = style.shadowOpacity
            wrapperView.layer.shadowRadius = style.shadowRadius
            wrapperView.layer.shadowOffset = style.shadowOffset
        }
        
        if let image = image {
            imageView = UIImageView(image: image)
            imageView?.layer.cornerRadius = max(style.imageSize.width / 2, style.imageSize.height / 2)
            imageView?.layer.masksToBounds = true
            imageView?.contentMode = .scaleAspectFit
            imageView?.frame = CGRect(x: style.horizontalPadding, y: style.verticalPadding, width: style.imageSize.width, height: style.imageSize.height)
        }
        
        var imageRect = CGRect.zero
        
        if let imageView = imageView {
            imageRect.origin.x = style.horizontalPadding
            imageRect.origin.y = style.verticalPadding
            imageRect.size.width = imageView.bounds.size.width
            imageRect.size.height = imageView.bounds.size.height
        }
        

        
        if let title = title {
            titleLabel = UILabel()
            titleLabel?.numberOfLines = style.titleNumberOfLines
            titleLabel?.font = style.titleFont
            titleLabel?.textAlignment = style.titleAlignment
            titleLabel?.lineBreakMode = .byTruncatingTail
            titleLabel?.textColor = style.titleColor
            titleLabel?.backgroundColor = UIColor.clear
            titleLabel?.text = title;
            
            let maxTitleSize = CGSize(width: (self.bounds.size.width * style.maxWidthPercentage) - imageRect.size.width, height: self.bounds.size.height * style.maxHeightPercentage)
            let titleSize = titleLabel?.sizeThatFits(maxTitleSize)
            if let titleSize = titleSize {
                titleLabel?.frame = CGRect(x: 0.0, y: 0.0, width: titleSize.width, height: titleSize.height)
            }
        }
        
        if let message = message {
            messageLabel = UILabel()
            messageLabel?.text = message
            messageLabel?.numberOfLines = style.messageNumberOfLines
            messageLabel?.font = style.messageFont
            messageLabel?.textAlignment = style.messageAlignment
            messageLabel?.lineBreakMode = .byTruncatingTail;
            messageLabel?.textColor = style.messageColor
            messageLabel?.backgroundColor = UIColor.clear
            
            let maxMessageSize = CGSize(width: (self.bounds.size.width * style.maxWidthPercentage) - imageRect.size.width, height: self.bounds.size.height * style.maxHeightPercentage)
            let messageSize = messageLabel?.sizeThatFits(maxMessageSize)
            if let messageSize = messageSize {
                let actualWidth = min(messageSize.width, maxMessageSize.width)
                let actualHeight = min(messageSize.height, maxMessageSize.height)
                messageLabel?.frame = CGRect(x: 0.0, y: 0.0, width: actualWidth, height: actualHeight)
            }
        }
        
        var titleRect = CGRect.zero
        
        if let titleLabel = titleLabel {
            titleRect.origin.x = imageRect.origin.x + imageRect.size.width + style.horizontalPadding
            titleRect.origin.y = style.verticalPadding * 2
            titleRect.size.width = titleLabel.bounds.size.width
            titleRect.size.height = titleLabel.bounds.size.height
        }
        
        var messageRect = CGRect.zero
        
        if let messageLabel = messageLabel {
            messageRect.origin.x = imageRect.origin.x + imageRect.size.width + style.horizontalPadding
            messageRect.origin.y = titleRect.origin.y + titleRect.size.height
            messageRect.size.width = messageLabel.bounds.size.width
            messageRect.size.height = messageLabel.bounds.size.height
        }
        
        let longerWidth = max(titleRect.size.width, messageRect.size.width)
        let longerX = max(titleRect.origin.x, messageRect.origin.x)
        let wrapperWidth = max((imageRect.size.width + (style.horizontalPadding * 2.0)), (longerX + longerWidth + style.horizontalPadding))
        let wrapperHeight = max((messageRect.origin.y + messageRect.size.height + style.verticalPadding), (imageRect.size.height + (style.verticalPadding * 2.0)))
        
        wrapperView.frame = CGRect(x: 0.0, y: 0.0, width: wrapperWidth * 1.35, height: wrapperHeight)
        
        if let titleLabel = titleLabel {
            titleLabel.frame = titleRect
            wrapperView.addSubview(titleLabel)
        }
        
        if let messageLabel = messageLabel {
            messageLabel.frame = messageRect
            wrapperView.addSubview(messageLabel)
        }
        
        if let imageView = imageView {
            wrapperView.addSubview(imageView)
        }
        
        return wrapperView
    }
    
}

// MARK: - Toast Style
/**
 `ToastStyle` instances define the look and feel for toast views created via the
 `makeToast` methods as well for toast views created directly with
 `toastViewForMessage(message:title:image:style:)`.
 @warning `ToastStyle` offers relatively simple styling options for the default
 toast view. If you require a toast view with more complex UI, it probably makes more
 sense to create your own custom UIView subclass and present it with the `showToast`
 methods.
 */
public struct ToastStyle {
    
    public init() {}
    
    /**
     The background color. Default is `UIColor.blackColor()` at 80% opacity.
     */
    public var backgroundColor = UIColor.white.withAlphaComponent(0.99)
    
    /**
     The title color. Default is `UIColor.whiteColor()`.
     */
    public var titleColor = UIColor.black
    
    /**
     The message color. Default is `UIColor.whiteColor()`.
     */
    public var messageColor = UIColor.green
    
    /**
     A percentage value from 0.0 to 1.0, representing the maximum width of the toast
     view relative to it's superview. Default is 0.8 (80% of the superview's width).
     */
    public var maxWidthPercentage: CGFloat = 0.9 {
        didSet {
            maxWidthPercentage = max(min(maxWidthPercentage, 1.0), 0.0)
        }
    }
    
    /**
     A percentage value from 0.0 to 1.0, representing the maximum height of the toast
     view relative to it's superview. Default is 0.8 (80% of the superview's height).
     */
    public var maxHeightPercentage: CGFloat = 0.2 {
        didSet {
            maxHeightPercentage = max(min(maxHeightPercentage, 1.0), 0.0)
        }
    }
    
    /**
     The spacing from the horizontal edge of the toast view to the content. When an image
     is present, this is also used as the padding between the image and the text.
     Default is 10.0.
     */
    public var horizontalPadding: CGFloat = 16.0
    
    /**
     The spacing from the vertical edge of the toast view to the content. When a title
     is present, this is also used as the padding between the title and the message.
     Default is 10.0.
     */
    public var verticalPadding: CGFloat = 20.0
    
    /**
     The corner radius. Default is 10.0.
     */
    public var cornerRadius: CGFloat = 12.0;
    
    /**
     The title font. Default is `UIFont.boldSystemFontOfSize(16.0)`.
     */
    public var titleFont = UIFont.boldSystemFont(ofSize: 18.0)
    
    /**
     The message font. Default is `UIFont.systemFontOfSize(16.0)`.
     */
    public var messageFont = UIFont.systemFont(ofSize: 16.0)
    
    /**
     The title text alignment. Default is `NSTextAlignment.Left`.
     */
    public var titleAlignment = NSTextAlignment.left
    
    /**
     The message text alignment. Default is `NSTextAlignment.Left`.
     */
    public var messageAlignment = NSTextAlignment.left
    
    /**
     The maximum number of lines for the title. The default is 0 (no limit).
     */
    public var titleNumberOfLines = 0
    
    /**
     The maximum number of lines for the message. The default is 0 (no limit).
     */
    public var messageNumberOfLines = 0
    
    /**
     Enable or disable a shadow on the toast view. Default is `false`.
     */
    public var displayShadow = true
    
    /**
     The shadow color. Default is `UIColor.blackColor()`.
     */
    public var shadowColor = UIColor.black
    
    /**
     A value from 0.0 to 1.0, representing the opacity of the shadow.
     Default is 0.8 (80% opacity).
     */
    public var shadowOpacity: Float = 0.25 {
        didSet {
            shadowOpacity = max(min(shadowOpacity, 1.0), 0.0)
        }
    }
    
    /**
     The shadow radius. Default is 6.0.
     */
    public var shadowRadius: CGFloat = 12.0
    
    /**
     The shadow offset. The default is 4 x 4.
     */
    public var shadowOffset = CGSize(width: 4.0, height: 4.0)
    
    /**
     The image size. The default is 80 x 80.
     */
    public var imageSize = CGSize(width: 80.0, height: 80.0)
    
    /**
     The size of the toast activity view when `makeToastActivity(position:)` is called.
     Default is 100 x 100.
     */
    public var activitySize = CGSize(width: 100.0, height: 100.0)
    
    /**
     The fade in/out animation duration. Default is 0.2.
     */
    public var fadeDuration: TimeInterval = 0.3
    
}

// MARK: - Toast Manager
/**
 `ToastManager` provides general configuration options for all toast
 notifications. Backed by a singleton instance.
 */
public class ToastManager {
    
    /**
     The `ToastManager` singleton instance.
     
     */
    public static let shared = ToastManager()
    
    /**
     The shared style. Used whenever toastViewForMessage(message:title:image:style:) is called
     with with a nil style.
     
     */
    public var style = ToastStyle()
    
    /**
     Enables or disables tap to dismiss on toast views. Default is `true`.
     
     */
    public var isTapToDismissEnabled = true
    
    /**
     Enables or disables queueing behavior for toast views. When `true`,
     toast views will appear one after the other. When `false`, multiple toast
     views will appear at the same time (potentially overlapping depending
     on their positions). This has no effect on the toast activity view,
     which operates independently of normal toast views. Default is `true`.
     
     */
    public var isQueueEnabled = true
    
    /**
     The default duration. Used for the `makeToast` and
     `showToast` methods that don't require an explicit duration.
     Default is 3.0.
     
     */
    public var duration: TimeInterval = 3.0
    
    /**
     Sets the default position. Used for the `makeToast` and
     `showToast` methods that don't require an explicit position.
     Default is `ToastPosition.Bottom`.
     
     */
    public var position = ToastPosition.bottom
    
}

// MARK: - ToastPosition
public enum ToastPosition {
    case top
    case center
    case bottom
    
    fileprivate func centerPoint(forToast toast: UIView, inSuperview superview: UIView) -> CGPoint {
        let padding: CGFloat = ToastManager.shared.style.verticalPadding
        
        switch self {
        case .top:
            return CGPoint(x: superview.bounds.size.width / 2.0, y: superview.bounds.minY )
        case .center:
            return CGPoint(x: superview.bounds.size.width / 2.0, y: superview.bounds.size.height / 2.0 - (toast.bounds.height / 2))
        case .bottom:
            return CGPoint(x: superview.bounds.size.width / 2.0, y: superview.bounds.size.height)
        }
    }
}
