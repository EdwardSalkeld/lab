{ pkgs, ... }:

{
  services.photoview = {
    enable = true;
    package = pkgs.photoview.overrideAttrs (old: {
      # PhotoView 2.4.0 vendors libheif Go bindings written before libheif 1.23
      # renamed these CGo enum types to typedefs.
      preBuild = (old.preBuild or "") + ''
        substituteInPlace vendor/github.com/strukturag/libheif/go/heif/heif.go \
          --replace-fail C.enum_heif_compression_format C.heif_compression_format \
          --replace-fail C.enum_heif_chroma C.heif_chroma \
          --replace-fail C.enum_heif_colorspace C.heif_colorspace \
          --replace-fail C.enum_heif_channel C.heif_channel \
          --replace-fail 'uint32(compression)' 'C.heif_compression_format(compression)' \
          --replace-fail 'uint32(colorspace)' 'C.heif_colorspace(colorspace)' \
          --replace-fail 'uint32(chroma)' 'C.heif_chroma(chroma)' \
          --replace-fail 'uint32(channel)' 'C.heif_channel(channel)'
      '';
    });
    host = "127.0.0.1";
    mediaPath = "/data/full/photos/archive";
    settings = {
      disableFaceRecognition = true;
      disableVideoEncoding = true;
      disableRawProcessing = true;
    };
  };

  users.users.photoview.extraGroups = [ "data" ];

  systemd.services.photoview = {
    after = [ "data.mount" ];
    wants = [ "data.mount" ];
    unitConfig.ConditionPathIsMountPoint = [ "/data" ];
  };
}
