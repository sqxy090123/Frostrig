#+build windows
package frostrig_ffi

foreign import librandomx "system:randomx"

@(default_calling_convention = "c")
foreign librandomx {
}
