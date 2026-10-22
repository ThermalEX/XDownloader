const normalAvatarAsset = 'assets/branding/app_icon.png';
const playfulAvatarAsset = 'assets/branding/playful_avatar.png';

String appAvatarAsset(bool playful) =>
    playful ? playfulAvatarAsset : normalAvatarAsset;
