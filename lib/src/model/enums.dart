enum FlipperLink { usb, ble }

enum FlipperMode { disconnected, cli, rpc }

/// What happened to the link, so a listener reacts to the transition instead of
/// diffing snapshots it may not have seen.
///
/// One stream carries all four. Splitting "a different Flipper is in play" into
/// a stream of its own would make every listener join two and work out how the
/// two orders relate; here the client works the transition out once, where it
/// is the only thing that can.
enum FlipperConnectionEvent {
  /// A session is up and usable, and it is the same Flipper as before.
  connected,

  /// The link went away. [FlipperConnectionState.reconnecting] says whether one
  /// is being re-established.
  disconnected,

  /// An attempt is in flight and nothing is committed yet.
  connecting,

  /// A different Flipper is in play from here on. Everything device-scoped -
  /// what is installed, what the firmware is, what a page is showing - is now
  /// about another device.
  deviceChanged,

  /// Same link, same Flipper, different protocol.
  ///
  /// In practice this means CLI to RPC, and only that. The firmware offers no
  /// way to turn an RPC session into a CLI one, so going that way destroys the
  /// session and builds another: the teardown fails every request in flight and
  /// raises a real [disconnected], and the CLI session that follows arrives as
  /// an ordinary [connected]. Coming back the other way needs no teardown -
  /// `start_rpc_session` is written over the same transport - and that is the
  /// one transition a listener could otherwise miss entirely, because nothing
  /// about the link changed.
  ///
  /// So RPC work has no reason to watch for this. Losing RPC already reaches it
  /// as a disconnect, which is what it is. What this is for is the other
  /// direction: a CLI page holding a prompt needs to know the stream under it
  /// has just become protobuf, and anything that wants to act the moment RPC
  /// comes back has nothing else to key on.
  ///
  /// Never raised into or out of [FlipperMode.disconnected]. Coming up out of
  /// nothing is [connected]; going down to nothing is [disconnected].
  modeChanged,
}

/// Where a request sits in the send queue, and what that says about it.
///
/// The queue is strictly ordered by this, then first-come-first-served, so the
/// value is also the plainest statement of what a request is for. Declared in
/// those terms:
///
/// - [rightNow] jumps the queue. Control and cleanup that belongs to something
///   already running or already decided - the ping that paces an upload, the
///   delete of its half-written file, the stop that puts a screen stream out,
///   a reboot.
/// - [foreground] is what the screen is waiting on, and only that. Readings that
///   exist to be displayed - voltage, current, device info - and the window the
///   user just tapped. It follows whichever Flipper they are looking at, and a
///   Flipper that stops being looked at has nothing foreground left to do on it.
/// - [unattended] runs whether or not anyone is looking at that Flipper.
///   A device that asked for a location fix or for something off the internet is
///   owed an answer because it is connected, not because it is the one on
///   screen, and a second Flipper in a warm session must not wait its turn at
///   being looked at. The same holds for the ordinary business of a task -
///   listing a folder, making one, checking an md5, closing an app - which is
///   about the Flipper the task is on, not about the one in front of the user.
///   Above [background] deliberately: these are short and something is held up
///   by each of them, and queueing them behind a firmware upload would be the
///   one delay that matters.
/// - [background] is bulk work that belongs to one Flipper and outlives the
///   screen: uploading a firmware or an app, walking storage, mirroring files.
///   Low in the queue because it is long, not because it is unimportant.
///
/// Which device a request reaches is decided by the task it belongs to, not by
/// this - see `FlipperClient.runTask`. The two line up by construction: a
/// display reading is never inside a task, so it follows the active Flipper on
/// its own, while bulk work always is. Labelling bulk work [foreground] breaks
/// nothing about where it goes, but it puts a firmware upload ahead of the UI
/// in the queue and says the opposite of what it is.
enum FlipperRequestPriority { rightNow, foreground, unattended, background }
