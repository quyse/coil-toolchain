{ lib }:

rec {
  # util functions for parsing xml after conversion to JSON with xq

  getTags = tag: obj: let
    fields = obj."${tag}" or [];
  in if builtins.typeOf fields == "list" then fields else [fields];

  getTag = tag: obj: let
    tags = getTags tag obj;
  in assert lib.length tags == 1; lib.head tags;

  getAttrs = obj: with lib; pipe obj [
    attrNames
    (concatMap (attr: if hasPrefix "@" attr then [(nameValuePair (removePrefix "@" attr) obj."${attr}")] else []))
    listToAttrs
  ];

  getAttr = attr: obj: obj."@${attr}" or null;

  mkItems = itemOrItems:
    if builtins.typeOf itemOrItems == "list"
      then
        if lib.length itemOrItems == 1
          then lib.head itemOrItems
          else
            if lib.length itemOrItems == 0
              then null
              else itemOrItems
      else itemOrItems
    ;
}
