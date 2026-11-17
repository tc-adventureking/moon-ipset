///|
// Protocol inputs outside the public Byte type; never counted as library rejections.
let protocol_rejections : String =
  #|{"op":"address_bytes","bytes":[-1,-1,-1,-1]}
  #|{"op":"network_bytes","bytes":[-1,-1,-1,-1]}
  #|{"op":"network_bytes","bytes":[-1,-1,-1,-1],"prefix":0}
  #|{"op":"interface_bytes","bytes":[-1,-1,-1,-1]}
  #|{"op":"interface_bytes","bytes":[-1,-1,-1,-1],"prefix":0}
  #|{"op":"address_bytes","bytes":[256,256,256,256]}
  #|{"op":"network_bytes","bytes":[256,256,256,256]}
  #|{"op":"network_bytes","bytes":[256,256,256,256],"prefix":0}
  #|{"op":"interface_bytes","bytes":[256,256,256,256]}
  #|{"op":"interface_bytes","bytes":[256,256,256,256],"prefix":0}
