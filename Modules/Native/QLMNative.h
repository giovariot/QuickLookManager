#import <Foundation/Foundation.h>

//! Ponte verso le librerie C/C++ (LibRaw, libarchive): le legge qui, in ObjC, perché Swift non importa bene C++.
FOUNDATION_EXPORT double QLMNativeVersionNumber;
FOUNDATION_EXPORT const unsigned char QLMNativeVersionString[];

#import <QLMNative/QLMRawKit.h>
#import <QLMNative/QLMArchiveKit.h>
#import <QLMNative/QLMMediaKit.h>
