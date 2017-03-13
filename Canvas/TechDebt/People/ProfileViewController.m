//
// Copyright (C) 2016-present Instructure, Inc.
//   
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
    
    

#import <CanvasKit1/CanvasKit1.h>
#import <CanvasKit1/CKActionSheetWithBlocks.h>
#import <CanvasKit1/CKAlertViewWithBlocks.h>
#import <CanvasKit1/NSFileManager+CKAdditions.h>

#import "ProfileViewController.h"

#import "FolderViewController.h"
#import "AboutViewController.h"
#import "UIImage+ImageEffects.h"
#import "AFHTTPAvatarImageResponseSerializer.h"
#import "CBIMessageViewModel.h"
#import "CBIMessageDetailViewController.h"

#import "CBIConversationStarter.h"

#import <CanvasKeymaster/SupportTicketViewController.h>
#import "CKIClient+CBIClient.h"
#import "CKIUser+SwiftCompatibility.h"
#import "CKCanvasAPI+CurrentAPI.h"
#import "Analytics.h"

@import SoPretty;
@import CanvasKit;
@import CanvasKeymaster;
@import Peeps;
#import "CBILog.h"

#ifdef __APPLE__
#import "TargetConditionals.h"
#endif
#import "UIImage+TechDebt.h"

@interface ProfileViewController () <UIGestureRecognizerDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate, UIAlertViewDelegate, UIActionSheetDelegate>

@property (weak, nonatomic) IBOutlet UIBarButtonItem *simulatorMasqueradeButton;
@property (weak, nonatomic) IBOutlet UIButton *avatarButton;
@property UITapGestureRecognizer *keyboardDismissalGesture;
@property (weak, nonatomic) IBOutlet UIImageView *headerImageView;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *avatarButtonVerticalConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *headerImageViewVerticalConstraint;
@property (weak, nonatomic) IBOutlet UILabel *nameLabel;
@property (weak, nonatomic) IBOutlet UILabel *emailLabel;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *nameLabelVerticalConstraint;
@property (weak, nonatomic) IBOutlet UILabel *versionLabel;

@property (weak, nonatomic) IBOutlet UIButton *filesButton;
@property (strong, nonatomic) IBOutletCollection(UIButton) NSArray *buttons;
@property (weak, nonatomic) IBOutlet UIButton *sendMessageButton;
@property (weak, nonatomic) IBOutlet UIButton *logoutButton;
@property (strong, nonatomic) IBOutlet UIButton *settingsButton;
@property (strong, nonatomic) IBOutlet UIButton *helpButton;

@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *loadingIndicator;
@property (nonatomic) BOOL isHelpActionSheet;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *headerHeightContraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *headerCenterXConstraint;
@property (nonatomic, retain) NSLayoutConstraint *minHeaderHeight;
@property (strong, nonatomic) NSArray *headerMaxHeightConstraints;

@end


// TODO: Unify the iPad and iPhone storyboards for profile
@implementation ProfileViewController

- (id)init {
    return [[UIStoryboard storyboardWithName:@"Profile" bundle:[NSBundle bundleForClass:[self class]]] instantiateInitialViewController];
}

#pragma mark - View Lifecycle

CGFloat square(CGFloat x){return x*x;}

- (void)panned:(UIPanGestureRecognizer*) recognizer {
    [self.view layoutIfNeeded];
    
    CGPoint tranlation = [recognizer translationInView:self.view];
    
    /////////////////////
    // ALPHA CALCULATIONS
    CGFloat distanceToCompleteFade = 150;
    // Use a root to allow easy initial movement, then limited as the further you go
    // Equation of the form a*(y/a)^(1/3)
    CGFloat yDiff = tranlation.y > 0 ? distanceToCompleteFade*pow(tranlation.y/distanceToCompleteFade, 1/3.0) : 0;
    BOOL finished = recognizer.state == UIGestureRecognizerStateEnded;
    CGFloat alpha = (!finished) ? MAX(0, (distanceToCompleteFade-yDiff)/distanceToCompleteFade) : 1.0;

    //////////////////////
    // HEIGHT CALCULATIONS
    NSInteger heightPriority = (!finished) ? 999 : 100;
    CGFloat startHeight = 540.0/1364 * MIN(self.view.frame.size.width, self.view.frame.size.height);
    CGFloat yScale = 2/3.0;
    CGFloat headerHeight = startHeight + yDiff*yScale;
    self.headerHeightContraint.constant = headerHeight;
    self.headerHeightContraint.priority = heightPriority;

    for (NSLayoutConstraint *constraint in self.headerMaxHeightConstraints) {
        constraint.priority = (finished) ? 999 : 100;
    }
    ////////////
    // ANIMATING
    CGFloat animationDuration = finished ? 0.5 : 0;
    [UIView animateKeyframesWithDuration:animationDuration delay:0.0 options:UIViewKeyframeAnimationOptionAllowUserInteraction | UIViewKeyframeAnimationOptionBeginFromCurrentState animations:^{
        for (UIView *sub in self.view.subviews) {
            if (sub != self.headerImageView) {
                sub.alpha = alpha;
            }
        }
        [self.view layoutIfNeeded];
    } completion:nil];
    
}

- (void)viewDidLoad {
    [super viewDidLoad];

    Session *session = TheKeymaster.currentClient.authSession;
    
    [session updateBackdropFileFromServer:^(BOOL success) {
        [session backdropPhoto:^(UIImage *backdropPhoto) {
            self.headerImageView.image = backdropPhoto;
        }];
    }];

    UIPanGestureRecognizer *panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panned:)];
    [self.view addGestureRecognizer:panGestureRecognizer];
    
    
    self.navigationController.tabBarItem.selectedImage = [UIImage techDebtImageNamed:@"icon_profile_selected"];
    
    self.canvasAPI = [CKCanvasAPI currentAPI];
    if (! self.user) {
        self.user = self.canvasAPI.user;
    }
    
    BOOL masquerading = [CKIClient currentClient].actAsUserID != nil;
    if (masquerading) {
        UIBarButtonItem *masq = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Stop Masquerading", @"Button title for stopping masquerading; when a privileged user becomes another user in the system") style:UIBarButtonItemStylePlain target:self action:@selector(stopMasquerade)];
        self.navigationItem.rightBarButtonItem = masq;
    }
#if TARGET_IPHONE_SIMULATOR
    else {
        UIBarButtonItem *masq = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Masquerade", @"Button title for beginning masquerading") style:UIBarButtonItemStylePlain target:self action:@selector(masqueradeAsUser)];
        self.navigationItem.rightBarButtonItem = masq;
    }
#else
    else {
        self.navigationItem.rightBarButtonItem = nil;
    }
#endif
    
    NSDictionary *bundleInfo = [[NSBundle mainBundle] infoDictionary];
    NSString *versionString = [NSString stringWithFormat:@"v %@ (%@)", bundleInfo[@"CFBundleShortVersionString"], bundleInfo[@"CFBundleVersion"]];
    self.versionLabel.text = versionString;
    
    [self.nameLabel setText:self.user.displayName];
    [self.emailLabel setText:self.user.primaryEmail];
    [self.nameLabel setAlpha:0.0f];
    [self.emailLabel setAlpha:0.0f];
    [self.filesButton setTitle:NSLocalizedString(@"My Files", @"files button") forState:UIControlStateNormal];
    [self.logoutButton setTitle:NSLocalizedString(@"Logout", @"Title for a button to logout a user") forState:UIControlStateNormal];
    [self.settingsButton setTitle:NSLocalizedString(@"Settings", @"Title for Settings") forState:UIControlStateNormal];
    [self.helpButton setTitle:NSLocalizedString(@"Help", @"help button") forState:UIControlStateNormal];

    [@[self.filesButton, self.logoutButton, self.settingsButton, self.helpButton] enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger idx, BOOL * _Nonnull stop) {
    button.titleEdgeInsets = UIEdgeInsetsMake(0, 3, 0, 3);
    }];
    
    [self.avatarButton setAdjustsImageWhenHighlighted:NO];
    [self.avatarButton setContentMode:UIViewContentModeCenter];
    self.avatarButton.accessibilityIdentifier = @"profile_photo_button";
    self.avatarButton.accessibilityLabel = NSLocalizedString(@"Change Profile Image", @"button to change user's profile image");
    
    [self updateForUser];
    
    UITapGestureRecognizer *chooseCoverPicture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(chooseCoverPhoto)];
    [self.headerImageView addGestureRecognizer:chooseCoverPicture];
    self.headerImageView.userInteractionEnabled = YES;
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.view attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:self.headerImageView attribute:NSLayoutAttributeLeft multiplier:1.0 constant:0]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.view attribute:NSLayoutAttributeRight relatedBy:NSLayoutRelationLessThanOrEqual toItem:self.headerImageView attribute:NSLayoutAttributeRight multiplier:1.0 constant:0]];
    
    [self.avatarButton setClipsToBounds:YES];
    [self loadAvatar];
    self.headerImageView.backgroundColor = [UIColor lightGrayColor];
    
    CGFloat maxHeightMultiplier = 540.0/1364;
    NSLayoutConstraint *maxOnHeight = [NSLayoutConstraint constraintWithItem:self.headerImageView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationLessThanOrEqual toItem:self.view attribute:NSLayoutAttributeHeight multiplier:maxHeightMultiplier constant:0];
    maxOnHeight.priority = 999;
    [self.view addConstraint:maxOnHeight];
    NSLayoutConstraint *maxOnWidth = [NSLayoutConstraint constraintWithItem:self.headerImageView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationLessThanOrEqual toItem:self.view attribute:NSLayoutAttributeWidth multiplier:maxHeightMultiplier constant:0];
    maxOnWidth.priority = 999;
    [self.view addConstraint:maxOnWidth];
    self.headerMaxHeightConstraints = @[maxOnWidth, maxOnHeight];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

-(void)chooseCoverPhoto {
    @weakify(self);
    BackdropPickerViewController *backdropPicker = [[BackdropPickerViewController alloc] initWithSession:TheKeymaster.currentClient.authSession imageSelected:^(UIImage *selectedImage) {
        @strongify(self);
        self.headerImageView.image = selectedImage;
    }];
    [self.navigationController pushViewController:backdropPicker animated:YES];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self.view layoutIfNeeded];
    [self.buttons enumerateObjectsUsingBlock:^(UIButton *button, NSUInteger idx, BOOL *stop) {
        [button.layer setBorderWidth:2.0f];
        [button.layer setBorderColor:[Brand.current.tintColor CGColor]];
        [button setTintColor:Brand.current.tintColor];
        [button.layer setCornerRadius:button.bounds.size.height/2];
    }];
    
    [self.logoutButton.layer setBorderWidth:2.0f];
    [self.logoutButton.layer setBorderColor:[Brand.current.tintColor CGColor]];
    [self.logoutButton setTintColor:Brand.current.tintColor];
    [self.logoutButton.layer setCornerRadius:self.logoutButton.bounds.size.height/2];
    [self.logoutButton setBackgroundColor:[UIColor prettyOffWhite]];

    [self.avatarButton.layer setCornerRadius:self.avatarButton.frame.size.height/2];

    CALayer *borderLayer = [CALayer layer];
    CGRect borderFrame = CGRectMake(-1, -1, (self.avatarButton.frame.size.width + 2), (self.avatarButton.frame.size.height + 2));
    [borderLayer setBackgroundColor:[[UIColor clearColor] CGColor]];
    [borderLayer setFrame:borderFrame];
    [borderLayer setCornerRadius:self.avatarButton.frame.size.height/2];
    [borderLayer setBorderWidth:4.0f];
    [borderLayer setBorderColor:[[UIColor whiteColor] CGColor]];
    [self.avatarButton.layer addSublayer:borderLayer];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    DDLogVerbose(@"%@ - viewDidAppear", NSStringFromClass([self class]));
    [UIView animateWithDuration:0.5 animations:^{
        [self.nameLabel setAlpha:1.0f];
        [self.emailLabel setAlpha:1.0f];
        [self.view layoutIfNeeded];
    }];
}

-(void)setImage:(UIImage *)image {
    self.headerImageView.backgroundColor = [UIColor clearColor];
    [self.loadingIndicator stopAnimating];
    if (!image) image = [UIImage techDebtImageNamed:@"icon_student_fill"];
    if (self.profileImageSelected){
        self.profileImageSelected(image);
    }
        void (^gotPhoto)(UIImage*) = ^void(UIImage *backdropImage) {
            self.headerImageView.image = nil;
            if (!self.minHeaderHeight) {
                self.minHeaderHeight = [NSLayoutConstraint constraintWithItem:self.headerImageView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.0 constant:90];
                [self.view addConstraint:self.minHeaderHeight];
            }
            if (backdropImage) {
                self.headerImageView.image = backdropImage;
                self.minHeaderHeight.constant = 110;
            } else {
                self.headerImageView.image = [image applyLightEffect];
                self.minHeaderHeight.constant = 90;
            }
        };
        Session *session = [CKIClient currentClient].authSession;
        [session backdropPhoto:gotPhoto];

        [self.avatarButton setImage:image forState:UIControlStateNormal];
        [self.avatarButtonVerticalConstraint setConstant:10.0f];
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            [self.avatarButtonVerticalConstraint setConstant:30.0f];
        }
        [self.view layoutIfNeeded];

    [UIView animateWithDuration:0.25 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        [self.headerImageViewVerticalConstraint setConstant:0.0f];
        [self.view layoutIfNeeded];
    } completion:nil];
}

- (void)loadAvatar
{
    [self.loadingIndicator startAnimating];
    SessionUser *user = [CKIClient currentClient].currentUser.swiftUser;
    [user getAvatarImage:^(UIImage * _Nullable image, NSError * _Nullable error) {
        [self setImage:image];
    }];
}

#pragma mark - User

- (void)setUser:(CKUser *)user {
    _user = user;
    [self updateForUser];
}

- (void)updateForUser {
    if (self.canvasAPI.actAsId && ![self.canvasAPI.actAsId isEqualToString:[@(self.user.ident) description]]) {
        [self.canvasAPI getUserProfileWithBlock:^(NSError *error, BOOL isFinalValue) {
            if (!error && isFinalValue) {
                self.user = self.canvasAPI.user;
            }
        }];
        return;
    }
    self.emailLabel.text = self.user.primaryEmail;
    [self.nameLabel setText:self.user.displayName];
    
    self.title = NSLocalizedString(@"Profile", @"Title for profile screen");
    BOOL isPersonalProfile = [self isPersonalProfile];
    self.avatarButton.enabled = isPersonalProfile;
    
    for (UIButton *button in self.buttons) {
        button.hidden = !isPersonalProfile;
    }
    
    self.sendMessageButton.hidden = isPersonalProfile;
}

- (BOOL)isPersonalProfile {
    return self.user.ident == self.canvasAPI.user.ident;
}

#pragma mark - Gesture recognizer delegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return self.keyboardDismissalGesture != gestureRecognizer ||
    [self.nameLabel isFirstResponder] ||
    [self.emailLabel isFirstResponder];
}

#pragma mark - Settings Actions

- (IBAction)fileButtonPressed:(id)sender
{
    DDLogVerbose(@"fileButtonPressed");
    FolderViewController *folderController = [[FolderViewController alloc] initWithInterfaceStyle:FolderInterfaceStyleLight];
    folderController.canvasAPI = self.canvasAPI;
    folderController.title = NSLocalizedString(@"Files", @"Title for the files screen");
    CKContextInfo *context = [CKContextInfo contextInfoFromUser:self.user];
    [folderController loadRootFolderForContext:context];
    [self.navigationController pushViewController:folderController animated:YES];
}

#pragma mark - About Actions
- (IBAction)settingsButtonPressed:(id)sender {
    UIViewController *settings = self.settingsViewControllerFactory();
    [self.navigationController pushViewController:settings animated:YES];
}

#pragma mark - Logout

- (IBAction)logoutButtonPressed:(UIButton *)sender
{
    self.isHelpActionSheet = NO;
    DDLogVerbose(@"logoutButtonPressed");
    UIActionSheet *actionSheet;
    NSString *localizedTitle = NSLocalizedString(@"Are you ready to logout?", @"Action sheet title verifying that a user wants to logout.");
    NSString *localizedCancelButtonTitle = NSLocalizedString(@"Stay Logged In", @"button title for cancelling a logout.");
    NSString *localizedLogoutButtonTitle = NSLocalizedString(@"Logout", @"Title for a button to logout a user");
    
    actionSheet = [[UIActionSheet alloc] initWithTitle:localizedTitle delegate:self cancelButtonTitle:localizedCancelButtonTitle destructiveButtonTitle:localizedLogoutButtonTitle otherButtonTitles:NSLocalizedString(@"Change User", nil), nil];

    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        [actionSheet showFromRect:sender.bounds inView:sender animated:YES];
    } else {
        [actionSheet showFromTabBar:self.tabBarController.tabBar];
    }
    
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    
    if (self.isHelpActionSheet) {
        switch (buttonIndex) {
            case 0: // Report a Problem
                [SupportTicketViewController presentFromViewController: self supportTicketType: SupportTicketTypeProblem];
                break;
            case 1: // Request a mobile feature
                [SupportTicketViewController presentFromViewController: self supportTicketType: SupportTicketTypeFeatureRequest];
                break;
            default:
                break;
        }
    } else {
        // TODO: Unregister for remote notifications
        if (buttonIndex == actionSheet.destructiveButtonIndex) {
            [self dismissViewControllerAnimated:YES completion:^{
                [TheKeymaster logout];
                [self.navigationController popToRootViewControllerAnimated:YES];
            }];
        } else if (buttonIndex != actionSheet.cancelButtonIndex) {
            [self dismissViewControllerAnimated:YES completion:^{
                [TheKeymaster switchUser];
                [self.navigationController popToRootViewControllerAnimated:YES];
            }];
        }
    }
}

#pragma mark - Profile image setting

- (IBAction)pickAvatar:(id)sender
{
    UIButton *avatarButton = (UIButton *)sender;
    DDLogVerbose(@"pickAvatarPressed");
    CKActionSheetWithBlocks *actionSheet = [[CKActionSheetWithBlocks alloc] initWithTitle:NSLocalizedString(@"Choose Profile Picture", nil)];
    
    __weak __typeof(&*self)weakSelf = self;
    [actionSheet addButtonWithTitle:NSLocalizedString(@"Build Avatar", @"Link to building panda avatar") handler:^{
        PandatarBuilderViewController *pandatarBuilderViewController = [[PandatarBuilderViewController alloc] init];
        __weak PandatarBuilderViewController *pandatarBuilder = pandatarBuilderViewController;
        pandatarBuilderViewController.doneBuilding = ^(UIImage *tehPandatar) {
            [self imagePicker:nil pickedImage:tehPandatar];
            [pandatarBuilder dismissViewControllerAnimated:YES completion:nil];
        };
        pandatarBuilderViewController.canceledBuilding = ^{
            [pandatarBuilder dismissViewControllerAnimated:YES completion:nil];
        };
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController: pandatarBuilderViewController];
        navController.modalPresentationStyle = UIModalPresentationFormSheet;
        [weakSelf presentViewController:navController animated:YES completion:nil];
    }];
    
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [actionSheet addButtonWithTitle:NSLocalizedString(@"Take Photo", @"Button label for taking a photo") handler:^{
            DDLogVerbose(@"AvatarTakePhotoPressed");
            UIImagePickerController *imagePicker = [UIImagePickerController new];
            imagePicker.delegate = self;
            imagePicker.sourceType = UIImagePickerControllerSourceTypeCamera;
            imagePicker.allowsEditing = YES;
            [self presentViewController:imagePicker animated:YES completion:^{
                nil;
            }];
        }];
    }
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        [actionSheet addButtonWithTitle:NSLocalizedString(@"Choose Photo", @"Button label for choosing a photo") handler:^{
            DDLogVerbose(@"AvatarChoosePhotoPressed");
            UIImagePickerController *imagePicker = [UIImagePickerController new];
            imagePicker.delegate = self;
            imagePicker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
            imagePicker.allowsEditing = YES;
            imagePicker.modalPresentationStyle = UIModalPresentationPopover;
            imagePicker.popoverPresentationController.sourceView = avatarButton;
            imagePicker.popoverPresentationController.sourceRect = avatarButton.bounds;
            
            [self presentViewController:imagePicker animated:YES completion:nil];
        }];
    }
    [actionSheet addButtonWithTitle:NSLocalizedString(@"Add Cover Photo", nil) handler:^{
        [self chooseCoverPhoto];
    }];
    [actionSheet addCancelButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
    if (self.tabBarController) {
        [actionSheet showFromTabBar:self.tabBarController.tabBar];
    } else {
        [actionSheet showInView:self.view];
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingImage:(UIImage *)image editingInfo:(NSDictionary *)editingInfo {
    NSLog(@"Image Selected");
    [self dismissViewControllerAnimated:YES completion:nil];
    [self imagePicker:picker pickedImage:image];
}

- (void)imagePicker:(UIImagePickerController *)imagePicker pickedImage:(UIImage *)image {
    [self setImage:image];
    NSURL *imageFileURL = [self saveImageToFile:image];
    
    self.avatarButton.highlighted = YES;
    
    if (self.profileImageSelected){
        self.profileImageSelected(image);
    }
    
    UIActivityIndicatorView *activityIndicator = [UIActivityIndicatorView new];
    CGFloat x = CGRectGetMidX(self.avatarButton.bounds) - (activityIndicator.frame.size.width / 2.0f);
    CGFloat y = CGRectGetMidY(self.avatarButton.bounds) - (activityIndicator.frame.size.height / 2.0f);
    activityIndicator.frame = CGRectMake(x, y, activityIndicator.frame.size.width , activityIndicator.frame.size.height);
    [self.avatarButton addSubview:activityIndicator];
    [activityIndicator startAnimating];
    
    __weak CKCanvasAPI *weakAPI = self.canvasAPI;
    __weak ProfileViewController *weakSelf = self;
    void (^gotPhoto)(UIImage*) = ^void(UIImage *backdropImage) {
        self.headerImageView.image = nil;
        if (backdropImage) {
            self.headerImageView.image = backdropImage;
        } else {
            self.headerImageView.image = [image applyLightEffect];
        }
    };
    [self.canvasAPI postAvatarNamed:nil fileURL:imageFileURL block:^(NSError *error, BOOL isFinalValue, CKAttachment *attachment) {
        
        if (isFinalValue) {
            [weakSelf.avatarButton setImage:image forState:UIControlStateNormal];

            Session *session = [CKIClient currentClient].authSession;
            [session backdropPhoto:gotPhoto];
            weakSelf.canvasAPI.user.avatarURL = attachment.directDownloadURL;
            [weakAPI updateLoggedInUserAvatarWithURL:attachment.directDownloadURL block:^(NSError *error, BOOL isFinalValue, NSDictionary *dictionary) {
                if (error) {
                    NSLog(@"Error setting default avatar: %@", error.localizedDescription);
                }
            }];
            
            [activityIndicator stopAnimating];
            [activityIndicator removeFromSuperview];
            weakSelf.avatarButton.highlighted = NO;
        }
        if (error) {
            NSString *title = NSLocalizedString(@"Error", nil);
            NSString *message = NSLocalizedString(@"Unable to upload to server", @"message saying that avatar couldn't be loaded to server");
            CKAlertViewWithBlocks *alertView = [[CKAlertViewWithBlocks alloc] initWithTitle:title message:message];
            [alertView addButtonWithTitle:NSLocalizedString(@"OK", nil) handler:^{}];
            [alertView show];
            return;
        }
        
        [weakSelf.avatarButton setImage:image forState:UIControlStateNormal];
        Session *session = [CKIClient currentClient].authSession;
        
        [session backdropPhoto:gotPhoto];
        weakSelf.canvasAPI.user.avatarURL = attachment.directDownloadURL;
        [weakAPI updateLoggedInUserAvatarWithURL:attachment.directDownloadURL block:^(NSError *error, BOOL isFinalValue, NSDictionary *dictionary) {
            if (error) {
                NSLog(@"Error setting default avatar: %@", error.localizedDescription);
            }
        }];
        
    }];
}

- (NSURL *)saveImageToFile:(UIImage *)image {
    NSURL *fileURL = nil;
    
    CGFloat compression = 0.3f;
    CGFloat maxCompression = 0.1f;
    int maxFileSize = 40*1024;
    
    NSData *imageData = UIImageJPEGRepresentation(image, compression);
    
    while ([imageData length] > maxFileSize && compression > maxCompression)
    {
        compression -= 0.1;
        imageData = UIImageJPEGRepresentation(image, compression);
    }
    
    // Save the image to the filesystem    
    NSFileManager *fileManager = [NSFileManager new];
    NSURL *uniqueSaveURL = [fileManager uniqueFileURLWithURL:[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"profilePic.jpg"]]];
    
    BOOL result = [imageData writeToURL:uniqueSaveURL atomically:YES];
    if (!result) {
        NSLog(@"Saving the file failed. We should use some default image instead");
    } else {
        fileURL = uniqueSaveURL;
    }
    
    return fileURL;
}

#pragma mark - Masquerade

- (void)masqueradeAsUser
{
    NSString *title = NSLocalizedString(@"Masquerade", nil);
    NSString *message = NSLocalizedString(@"Enter User ID and Domain.", @"masquerade prompt");
    UIAlertController *masq = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:
                               UIAlertControllerStyleAlert];

    __block UITextField *userIDField = nil;
    [masq addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = NSLocalizedString(@"User ID", nil);
        textField.keyboardType = UIKeyboardTypeNumberPad;
        userIDField = textField;
    }];
    
    __block UITextField *domainField = nil;
    NSString *hostname = TheKeymaster.currentClient.baseURL.host;
    [masq addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.text = hostname;
        textField.keyboardType = UIKeyboardTypeURL;
        textField.placeholder = NSLocalizedString(@"Domain", nil);
        
        domainField = textField;
    }];
    
    NSString *cancel = NSLocalizedString(@"Cancel", nil);
    [masq addAction:[UIAlertAction actionWithTitle:cancel style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        [userIDField resignFirstResponder];
        [domainField resignFirstResponder];
        DDLogVerbose(@"masqueradeAsUserCancelled");
    }]];
    

    [masq addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        DDLogVerbose(@"masqueradeAsUserSubmit");
        [userIDField resignFirstResponder];
        [domainField resignFirstResponder];
        [self masquerade:userIDField.text domain:domainField.text];
    }]];
    
    [self presentViewController:masq animated:true completion:nil];
}

- (void)masquerade:(NSString *)masqueradeAs domain:(NSString *)domain
{
    if (masqueradeAs.length > 0) {
        [[TheKeymaster masqueradeAsUserWithID:masqueradeAs domain:domain] subscribeNext:^(id client) {
            [self dismissViewControllerAnimated:false completion:nil];
            DDLogVerbose(@"masqueradeAsUserSuccess : %@", [CKIClient currentClient].currentUser.id);
            CKAlertViewWithBlocks *alert = [[CKAlertViewWithBlocks alloc] initWithTitle:NSLocalizedString(@"Success!", @"Masquerade success title") message:[NSString stringWithFormat:NSLocalizedString(@"You are now masquerading as %@", @"Masquerade title telling who you are masquerading as"), [CKIClient currentClient].currentUser.name]];
            [alert addCancelButtonWithTitle:NSLocalizedString(@"OK", nil)];
            [alert show];
        } error:^(NSError *error) {
            DDLogVerbose(@"masqueradeAsUserError : %@", [error localizedDescription]);

            CKAlertViewWithBlocks *alert = [[CKAlertViewWithBlocks alloc] initWithTitle:NSLocalizedString(@"Oops!", nil) message:NSLocalizedString(@"You don't have permission to masquerade as this user or there is no user with that ID", @"Masquerade error message")];
            [alert addCancelButtonWithTitle:NSLocalizedString(@"OK", nil)];
            [alert show];
        }];
    }
}

- (void)stopMasquerade
{
    DDLogVerbose(@"stopMasqueradePressed");
    [TheKeymaster stopMasquerading];
}

- (IBAction)helpButtonTouched:(UIButton *)sender
{
    self.isHelpActionSheet = YES;
    DDLogVerbose(@"helpButtonTouched");
    [Analytics logScreenView: @"View Help Options"];
    
    UIActionSheet *helpSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", "Cancel button title") destructiveButtonTitle:nil otherButtonTitles:NSLocalizedString(@"Report a problem", "option to report a problem"), NSLocalizedString(@"Request a feature", "option to request a feature"), nil];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        [helpSheet showFromRect:sender.bounds inView:sender animated:YES];
    } else {
        [helpSheet showFromTabBar:self.tabBarController.tabBar];
    }    
}

- (IBAction)masqueradeButtonClicked:(id)sender
{
    DDLogVerbose(@"masqueradeButtonPressed");
    [self masqueradeAsUser];
}

- (void)addMotionEffectToView:(UIView *)view
{
    // Set vertical effect
    UIInterpolatingMotionEffect *verticalMotionEffect = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.y" type:UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis];
    verticalMotionEffect.minimumRelativeValue = @(-6);
    verticalMotionEffect.maximumRelativeValue = @(6);
    
    // Set horizontal effect
    UIInterpolatingMotionEffect *horizontalMotionEffect = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.x" type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
    horizontalMotionEffect.minimumRelativeValue = @(-6);
    horizontalMotionEffect.maximumRelativeValue = @(6);
    
    // Create group to combine both
    UIMotionEffectGroup *group = [UIMotionEffectGroup new];
    group.motionEffects = @[horizontalMotionEffect, verticalMotionEffect];
    
    // Add both effects to your view
    [view addMotionEffect:group];
}

- (void)addBackMotionEffectToView:(UIView *)view
{
    // Set vertical effect
    UIInterpolatingMotionEffect *verticalMotionEffect = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.y" type:UIInterpolatingMotionEffectTypeTiltAlongVerticalAxis];
    verticalMotionEffect.minimumRelativeValue = @(20);
    verticalMotionEffect.maximumRelativeValue = @(-20);
    
    // Set horizontal effect
    UIInterpolatingMotionEffect *horizontalMotionEffect = [[UIInterpolatingMotionEffect alloc] initWithKeyPath:@"center.x" type:UIInterpolatingMotionEffectTypeTiltAlongHorizontalAxis];
    horizontalMotionEffect.minimumRelativeValue = @(20);
    horizontalMotionEffect.maximumRelativeValue = @(-20);
    
    // Create group to combine both
    UIMotionEffectGroup *group = [UIMotionEffectGroup new];
    group.motionEffects = @[horizontalMotionEffect, verticalMotionEffect];
    
    // Add both effects to your view
    [view addMotionEffect:group];
}

- (IBAction)sendMessageButtonPressed:(id)sender {
    DDLogVerbose(@"sendMessageButtonPressed");
    CKConversationRecipient *recipient = [[CKConversationRecipient alloc] initWithInfo:@{@"id": @(self.user.ident), @"name": self.user.name}];
    [[CBIConversationStarter sharedConversationStarter] startAConversationWithRecipients:@[recipient]];
}


@end
