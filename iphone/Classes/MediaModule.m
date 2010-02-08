/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2010 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */

#import "MediaModule.h"
#import "TiUtils.h"
#import "TiBlob.h"
#import "TiFile.h"
#import "TitaniumApp.h"
#import "Mimetypes.h"

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVAudioPlayer.h>
#import <MediaPlayer/MediaPlayer.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import <QuartzCore/QuartzCore.h>

enum  
{
	MediaModuleErrorUnknown,
	MediaModuleErrorImagePickerBusy,
	MediaModuleErrorNoCamera,
	MediaModuleErrorNoVideo
};

@implementation MediaModule

#pragma mark Internal

-(void)dealloc
{
	RELEASE_TO_NIL(picker);
	RELEASE_TO_NIL(pickerSuccessCallback);
	RELEASE_TO_NIL(pickerErrorCallback);
	RELEASE_TO_NIL(pickerCancelCallback);
	[super dealloc];
}

-(void)destroyPicker
{
	RELEASE_TO_NIL(picker);
	RELEASE_TO_NIL(pickerSuccessCallback);
	RELEASE_TO_NIL(pickerErrorCallback);
	RELEASE_TO_NIL(pickerCancelCallback);
}

-(void)sendPickerError:(int)code
{
	if (pickerErrorCallback!=nil)
	{
		NSDictionary *event = [NSDictionary dictionaryWithObjectsAndKeys:NUMBOOL(false),@"success",NUMINT(code),@"code",nil];
		[self _fireEventToListener:@"error" withObject:event listener:pickerErrorCallback thisObject:nil];
	}
	[self destroyPicker];
}

-(void)sendPickerCancel
{
	if (pickerCancelCallback!=nil)
	{
		[self _fireEventToListener:@"cancel" withObject:nil listener:pickerCancelCallback thisObject:nil];
	}
	[self destroyPicker];
}

-(void)sendPickerSuccess:(id)event
{
	if (pickerSuccessCallback!=nil)
	{
		[self _fireEventToListener:@"success" withObject:event listener:pickerSuccessCallback thisObject:nil];
	}
	if (autoHidePicker)
	{
		[self destroyPicker];
	}
}

-(void)showPicker:(NSDictionary*)args isCamera:(BOOL)isCamera
{
	if (picker!=nil)
	{
		[self sendPickerError:MediaModuleErrorImagePickerBusy];
		return;
	}
	
	picker = [[UIImagePickerController alloc] init];
	[picker setDelegate:self];
	
	animatedPicker = YES;
	saveToRoll = NO;
	
	if (args!=nil)
	{
		pickerSuccessCallback = [args objectForKey:@"success"];
		ENSURE_TYPE_OR_NIL(pickerSuccessCallback,KrollCallback);
		[pickerSuccessCallback retain];
		
		pickerErrorCallback = [args objectForKey:@"error"];
		ENSURE_TYPE_OR_NIL(pickerErrorCallback,KrollCallback);
		[pickerErrorCallback retain];
		
		pickerCancelCallback = [args objectForKey:@"cancel"];
		ENSURE_TYPE_OR_NIL(pickerCancelCallback,KrollCallback);
		[pickerCancelCallback retain];
		
		// we use this to determine if we should hide the camera after taking 
		// a picture/video -- you can programmatically take multiple pictures
		// and use your own controls so this allows you to control that
		autoHidePicker = [TiUtils boolValue:@"autohide" properties:args def:YES];

		animatedPicker = [TiUtils boolValue:@"animated" properties:args def:YES];
		
		NSNumber * imageEditingObject = [args objectForKey:@"allowImageEditing"];  //backwards compatible
		saveToRoll = [TiUtils boolValue:@"saveToPhotoGallery" properties:args def:NO];
		
		if (imageEditingObject==nil)
		{
			imageEditingObject = [args objectForKey:@"allowEditing"];
		}
		
		// introduced in 3.1
		[picker setAllowsEditing:[TiUtils boolValue:imageEditingObject]];
		
		NSArray *sourceTypes = [UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeCamera];
		id types = [args objectForKey:@"mediaTypes"];
		
		BOOL movieRequired = NO;
		BOOL imageRequired = NO;
		
		if ([types isKindOfClass:[NSArray class]])
		{
			for (int c=0;c<[types count];c++)
			{
				if ([[types objectAtIndex:c] isEqualToString:(NSString*)kUTTypeMovie])
				{
					movieRequired = YES;
				}
				else if ([[types objectAtIndex:c] isEqualToString:(NSString*)kUTTypeImage])
				{
					imageRequired = YES;
				}
			}
			picker.mediaTypes = [NSArray arrayWithArray:types];
		}
		else if ([types isKindOfClass:[NSString class]])
		{
			if ([types isEqualToString:(NSString*)kUTTypeMovie] && ![sourceTypes containsObject:(NSString *)kUTTypeMovie])
			{
				// no movie type supported...
				[self sendPickerError:MediaModuleErrorNoVideo];
				return;
			}
			picker.mediaTypes = [NSArray arrayWithObject:types];
		}
		
		
		// if we require movie but not image and we don't support movie, bail...
		if (movieRequired == YES && imageRequired == NO && ![sourceTypes containsObject:(NSString *)kUTTypeMovie])
		{
			// no movie type supported...
			[self sendPickerError:MediaModuleErrorNoCamera];
			return ;
		}
		
		// introduced in 3.1
		id videoMaximumDuration = [args objectForKey:@"videoMaximumDuration"];
		if ([videoMaximumDuration respondsToSelector:@selector(doubleValue)] && [picker respondsToSelector:@selector(setVideoMaximumDuration:)])
		{
			[picker setVideoMaximumDuration:[videoMaximumDuration doubleValue]];
		}
		id videoQuality = [args objectForKey:@"videoQuality"];
		if ([videoQuality respondsToSelector:@selector(doubleValue)] && [picker respondsToSelector:@selector(setVideoQuality:)])
		{
			[picker setVideoQuality:[videoQuality doubleValue]];
		}
	}
	
	// do this afterwards above so we can first check for video support
	
	UIImagePickerControllerSourceType ourSource = (isCamera ? UIImagePickerControllerSourceTypeCamera : UIImagePickerControllerSourceTypePhotoLibrary);
	if (![UIImagePickerController isSourceTypeAvailable:ourSource])
	{
		[self sendPickerError:MediaModuleErrorNoCamera];
		return;
	}
	[picker setSourceType:ourSource];
	
	[[TitaniumApp app] showModalController:picker animated:animatedPicker];
}

#pragma mark Public APIs

MAKE_SYSTEM_PROP(UNKNOWN_ERROR,MediaModuleErrorUnknown);
MAKE_SYSTEM_PROP(DEVICE_BUSY,MediaModuleErrorImagePickerBusy);
MAKE_SYSTEM_PROP(NO_CAMERA,MediaModuleErrorNoCamera);
MAKE_SYSTEM_PROP(NO_VIDEO,MediaModuleErrorNoVideo);

MAKE_SYSTEM_PROP(VIDEO_CONTROL_DEFAULT,MPMovieControlModeDefault);
MAKE_SYSTEM_PROP(VIDEO_CONTROL_VOLUME_ONLY,MPMovieControlModeVolumeOnly);
MAKE_SYSTEM_PROP(VIDEO_CONTROL_HIDDEN,MPMovieControlModeHidden);
MAKE_SYSTEM_PROP(VIDEO_SCALING_NONE,MPMovieScalingModeNone);
MAKE_SYSTEM_PROP(VIDEO_SCALING_ASPECT_FIT,MPMovieScalingModeAspectFit);
MAKE_SYSTEM_PROP(VIDEO_SCALING_ASPECT_FILL,MPMovieScalingModeAspectFill);
MAKE_SYSTEM_PROP(VIDEO_SCALING_MODE_FILL,MPMovieScalingModeFill);

MAKE_SYSTEM_STR(MEDIA_TYPE_VIDEO,kUTTypeMovie);
MAKE_SYSTEM_STR(MEDIA_TYPE_PHOTO,kUTTypeImage);

MAKE_SYSTEM_PROP(QUALITY_HIGH,UIImagePickerControllerQualityTypeHigh);
MAKE_SYSTEM_PROP(QUALITY_MEDIUM,UIImagePickerControllerQualityTypeMedium);
MAKE_SYSTEM_PROP(QUALITY_LOW,UIImagePickerControllerQualityTypeLow);

-(NSArray*)availableCameraMediaTypes
{
	NSArray* mediaSourceTypes = [UIImagePickerController availableMediaTypesForSourceType: UIImagePickerControllerSourceTypeCamera];
	return mediaSourceTypes==nil ? [NSArray arrayWithObject:(NSString*)kUTTypeImage] : mediaSourceTypes;
}

-(NSArray*)availablePhotoMediaTypes
{
	NSArray* photoSourceTypes = [UIImagePickerController availableMediaTypesForSourceType: UIImagePickerControllerSourceTypePhotoLibrary];
	return photoSourceTypes==nil ? [NSArray arrayWithObject:(NSString*)kUTTypeImage] : photoSourceTypes;
}

-(NSArray*)availablePhotoGalleryMediaTypes
{
	NSArray* albumSourceTypes = [UIImagePickerController availableMediaTypesForSourceType: UIImagePickerControllerSourceTypeSavedPhotosAlbum];
	return albumSourceTypes==nil ? [NSArray arrayWithObject:(NSString*)kUTTypeImage] : albumSourceTypes;
}

-(id)isMediaTypeSupported:(id)args
{
	ENSURE_ARG_COUNT(args,2);
	
	NSString *media = [[TiUtils stringValue:[args objectAtIndex:0]] lowercaseString];
	NSString *type = [[TiUtils stringValue:[args objectAtIndex:1]] lowercaseString];
	
	NSArray *array = nil;
	
	if ([media isEqualToString:@"camera"])
	{
		array = [self availableCameraMediaTypes];
	}
	else if ([media isEqualToString:@"photo"])
	{
		array = [self availablePhotoMediaTypes];
	}
	else if ([media isEqualToString:@"photogallery"])
	{
		array = [self availablePhotoGalleryMediaTypes];
	}
	if (array!=nil)
	{
		for (NSString* atype in array)
		{
			if ([[atype lowercaseString] isEqualToString:type])
			{
				return NUMBOOL(YES);
			}
		}
	}
	return NUMBOOL(NO);
}

-(id)isCameraSupported:(id)arg
{
	return NUMBOOL([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]);
}

-(void)showCamera:(id)args
{
	ENSURE_UI_THREAD(showCamera,args);
	ENSURE_SINGLE_ARG_OR_NIL(args,NSDictionary);
	[self showPicker:args isCamera:YES];
}

-(void)openPhotoGallery:(id)args
{
	ENSURE_UI_THREAD(openPhotoGallery,args);
	ENSURE_SINGLE_ARG_OR_NIL(args,NSDictionary);
	[self showPicker:args isCamera:NO];
}	

-(void)takeScreenshot:(id)arg
{
	ENSURE_UI_THREAD(takeScreenshot,arg);
	ENSURE_SINGLE_ARG(arg,KrollCallback);
	
	// we take the shot of the whole window, not just the active view
	UIWindow *screenWindow = [[UIApplication sharedApplication] keyWindow];
	UIGraphicsBeginImageContext(screenWindow.bounds.size);
	[screenWindow.layer renderInContext:UIGraphicsGetCurrentContext()];
	UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	
	TiBlob *blob = [[[TiBlob alloc] initWithImage:image] autorelease];
	[self _fireEventToListener:@"screenshot" withObject:blob listener:arg thisObject:nil];
}

-(void)saveToPhotoGallery:(id)arg
{
	ENSURE_UI_THREAD(saveToPhotoGallery,arg);
	
	if ([arg isKindOfClass:[TiBlob class]])
	{
		TiBlob *blob = (TiBlob*)arg;
		NSString *mime = [blob mimeType];
		
		if (mime==nil || [mime hasPrefix:@"image/"])
		{
			UIImage * savedImage = [blob image];
			if (savedImage == nil) return;
			UIImageWriteToSavedPhotosAlbum(savedImage, nil, nil, NULL);
		}
		else if ([mime hasPrefix:@"video/"])
		{
			NSString * tempFilePath = [blob path];
			if (tempFilePath == nil) return;
			UISaveVideoAtPathToSavedPhotosAlbum(tempFilePath, nil, nil, NULL);
		}
	}
	else if ([arg isKindOfClass:[TiFile class]])
	{
		TiFile *file = (TiFile*)arg;
		NSString *mime = [Mimetypes mimeTypeForExtension:[file path]];
		if (mime == nil || [mime hasPrefix:@"image/"])
		{
			NSData *data = [NSData dataWithContentsOfFile:[file path]];
			UIImage *image = [[[UIImage alloc] initWithData:data] autorelease];
			UIImageWriteToSavedPhotosAlbum(image, nil, nil, NULL);
		}
		else if ([mime hasPrefix:@"video/"])
		{
			UISaveVideoAtPathToSavedPhotosAlbum([file path], nil, nil, NULL);
		}
	}
	else
	{
		[self throwException:@"invalid media type" subreason:[NSString stringWithFormat:@"expected either TiBlob or TiFile, was: %@",[arg class]] location:CODELOCATION];
	}
}

-(void)beep:(id)args
{
	ENSURE_UI_THREAD(beep,args);
	AudioServicesPlayAlertSound(kSystemSoundID_Vibrate);
}

-(void)vibrate:(id)args
{
	ENSURE_UI_THREAD(beep,args);
	AudioServicesPlayAlertSound(kSystemSoundID_Vibrate);
}

-(void)takePicture:(id)args
{
	// must have a picker, doh
	if (picker==nil)
	{
		[self throwException:@"invalid state" subreason:nil location:CODELOCATION];
	}
	ENSURE_UI_THREAD(takePicture,args);
	[picker takePicture];
}

-(void)hideCamera:(id)args
{
	ENSURE_UI_THREAD(hideCamera,args);
	if (picker!=nil)
	{
		[self destroyPicker];
	}
}

#pragma mark Delegates

- (void)imagePickerController:(UIImagePickerController *)picker_ didFinishPickingMediaWithInfo:(NSDictionary *)editingInfo
{
	[[picker parentViewController] dismissModalViewControllerAnimated:animatedPicker];
	
	NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
	
	TiBlob *media = nil;
	TiBlob *media2 = nil;
	
	NSString *mediaType = [editingInfo objectForKey:UIImagePickerControllerMediaType];
	if (mediaType==nil)
	{
		mediaType = (NSString*)kUTTypeImage; // default to in case older OS
	}
	
	[dictionary setObject:mediaType forKey:@"mediaType"];
	
	BOOL imageWrittenToAlbum = NO;
	BOOL isVideo = [mediaType isEqualToString:(NSString*)kUTTypeMovie];
	
	NSURL *mediaURL = [editingInfo objectForKey:UIImagePickerControllerMediaURL];
	if (mediaURL!=nil)
	{
		// this is a video, get the path to the URL
		media = [[[TiBlob alloc] initWithFile:[mediaURL path]] autorelease];
		
		if (isVideo)
		{
			[media setMimeType:@"video/mpeg" type:TiBlobTypeFile];
		}
		else 
		{
			[media setMimeType:@"image/jpeg" type:TiBlobTypeImage];
		}
		
		if (saveToRoll)
		{
			if (isVideo)
			{
				NSString *tempFilePath = [mediaURL absoluteString];
				UISaveVideoAtPathToSavedPhotosAlbum(tempFilePath, nil, nil, NULL);
			}
			else 
			{
				UIImage *image = [editingInfo objectForKey:UIImagePickerControllerOriginalImage];
				UIImageWriteToSavedPhotosAlbum(image, nil, nil, NULL);
				imageWrittenToAlbum = YES;
			}
			
		}
		
		// this is the thumbnail of the video
		if (isVideo)
		{
			UIImage *image = [editingInfo objectForKey:UIImagePickerControllerOriginalImage];
			media2 = [[[TiBlob alloc] initWithImage:image] autorelease];
		}
	}
	
	if (media==nil)
	{
		UIImage *image = [editingInfo objectForKey:UIImagePickerControllerEditedImage];
		if (image==nil)
		{
			image = [editingInfo objectForKey:UIImagePickerControllerOriginalImage];
		}
		media = [[[TiBlob alloc] initWithImage:image] autorelease];
		if (saveToRoll && imageWrittenToAlbum==NO)
		{
			UIImageWriteToSavedPhotosAlbum(image, nil, nil, NULL);
		}
	}
	
	NSValue * ourRectValue = [editingInfo objectForKey:UIImagePickerControllerCropRect];
	if (ourRectValue != nil)
	{
		CGRect ourRect = [ourRectValue CGRectValue];
		[dictionary setObject:[NSDictionary dictionaryWithObjectsAndKeys:
							   [NSNumber numberWithFloat:ourRect.origin.x],@"x",
							   [NSNumber numberWithFloat:ourRect.origin.y],@"y",
							   [NSNumber numberWithFloat:ourRect.size.width],@"width",
							   [NSNumber numberWithFloat:ourRect.size.height],@"height",
							   nil] forKey:@"cropRect"];
	}
	
	if (media!=nil)
	{
		[dictionary setObject:media forKey:@"media"];
	}
	
	if (media2!=nil)
	{
		[dictionary setObject:media2 forKey:@"thumbnail"];
	}
	
	[self sendPickerSuccess:dictionary];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker_
{
	[[picker parentViewController] dismissModalViewControllerAnimated:animatedPicker];
	[self sendPickerCancel];
}


@end
