{
  symlinkJoin,
  bbmb-server,
  chattingPackages,
}:

symlinkJoin {
  name = "chatting-runtime";
  paths = [
    bbmb-server
    chattingPackages.chatting-handler
    chattingPackages.chatting-platform
    chattingPackages.chatting-worker
  ];
}
