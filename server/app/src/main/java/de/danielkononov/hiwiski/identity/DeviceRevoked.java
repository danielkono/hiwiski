package de.danielkononov.hiwiski.identity;

import java.util.UUID;

/**
 * A device was signed out — by itself, or from another device in the device list.
 *
 * <p>Its token stops working at once; this tells whoever holds a connection open for it
 * (the event stream) to let the device know, so it shows the sign-in instead of waiting
 * for its next call to fail.
 */
public record DeviceRevoked(UUID deviceId) {}
