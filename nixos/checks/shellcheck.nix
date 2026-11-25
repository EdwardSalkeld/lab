# Shellchecks the shell this repo embeds in its NixOS configs: the systemd
# script fields its modules define, and the writeShellScript outputs listed in
# alcachofa.shellScripts.
{
  lib,
  pkgs,
  nixosConfigurations,
  repoRoot,
}:
let
  inRepo = file: lib.hasPrefix "${toString repoRoot}/" (toString file);

  # Definitions are raw module values, so open up mkIf/mkMerge/mkBefore and
  # friends to reach the strings this repo actually wrote.
  unwrap =
    value:
    if builtins.isAttrs value && value ? _type then
      if value._type == "if" then
        lib.optionals value.condition (unwrap value.content)
      else if value._type == "merge" then
        lib.concatMap unwrap value.contents
      else if value._type == "override" || value._type == "order" then
        unwrap value.content
      else
        [ value ]
    else
      [ value ];

  scriptFields = [
    "script"
    "preStart"
    "postStart"
    "reload"
    "preStop"
    "postStop"
  ];

  fieldTexts =
    unit: field: lib.optionals (builtins.isAttrs unit && unit ? ${field}) (unwrap unit.${field});

  serviceScripts =
    host: service: value:
    lib.concatMap (
      unit:
      lib.concatMap (
        field:
        map (text: {
          name = "${host}-${service}-${field}";
          inherit text;
        }) (fieldTexts unit field)
      ) scriptFields
    ) (unwrap value);

  repoDefinitions =
    system:
    builtins.filter (
      definition: inRepo definition.file
    ) system.options.systemd.services.definitionsWithLocations;

  unitScripts =
    host: system:
    lib.concatMap (
      definition:
      lib.concatMap (services: lib.concatLists (lib.mapAttrsToList (serviceScripts host) services)) (
        unwrap definition.value
      )
    ) (repoDefinitions system);

  writtenScripts =
    host: system:
    map (script: {
      name = "${host}-${script.name}";
      inherit (script) text;
    }) system.config.alcachofa.shellScripts;

  scripts = lib.concatLists (
    lib.mapAttrsToList (
      host: system: unitScripts host system ++ writtenScripts host system
    ) nixosConfigurations
  );

  # Store paths in the text are only words to shellcheck, so drop their context
  # rather than make the check build every package a script mentions.
  scriptFile =
    script: builtins.toFile "shellcheck-input" (builtins.unsafeDiscardStringContext script.text);
in
pkgs.runCommand "nix-shellcheck" { nativeBuildInputs = [ pkgs.shellcheck ]; } ''
  mkdir scripts
  ${lib.concatImapStrings (index: script: ''
    cp ${scriptFile script} scripts/${toString index}-${lib.escapeShellArg script.name}
  '') scripts}
  # systemd runs unit scripts with bash, but their text has no shebang.
  shellcheck --shell=bash scripts/*
  touch "$out"
''
