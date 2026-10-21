// Settings redesign: the mod's own pages in the system font at Settings' sizes (Settings/SGSettingsLook.h), on the
// inset grouped cards they already stand on. Spotify's own settings stay as Spotify draws them.
#import "Core/SGCore.h"
#import "Settings/SGSettingsLook.h"

%ctor {
    if (!SGRedesignedUI()) return;
    SGPagesNativeLook = YES;
}
