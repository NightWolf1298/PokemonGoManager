require 'oily_png'
Loc = Struct.new(:x, :y)
SSLoc = Struct.new(:loc, :color)

# NOTE: Please read the instructions!
# 1) Put phone in Do Not Disturb mode (notifications will interrupt screenshots)
# 2) Start Pokemon Go
# 3) Start Poke Genie
# 4) Open the Pokemon list, and do whatever sorting/filtering you want to select the Pokemon you want to rename
# 5) Set the desired number of Pokemon to rename:
POKEMON_TO_PROCESS = 1
# 6) Tap the Pokemon you want to start at, so its info is showing
# 7) RUN
# 8) DO NOT TOUCH YOUR PHONE WHILE RUNNING - tapping is done by coordinates regardless of what's on screen, so manually
#    playing with it may cause taps on unintended parts of the screen

# DO NOT EDIT BELOW HERE UNLESS YOUR UI SETTINGS ARE DIFFERENT
# (e.g. different phone)

# Reference screen size of my phone (Google Pixel 4 XL)
# coordinates will be scaled relative to this
REF_SIZE = Loc.new(1440, 3040)

# Google Pixel 4 XL
PHONE_SIZE = Loc.new(1440, 3040)
PHONE_TOP_MARGIN = 0

# Google Pixel 5
# PHONE_SIZE = Loc.new(1080, 2340)
# PHONE_TOP_MARGIN = 150

# UI element locations (in pixels)
POKEMON_INFO_CLOSE_LOC = Loc.new(730, 2800)
POKEMON_INFO_MENU_LOC = Loc.new(1250, 2800)
POKEMON_INFO_APPRAISE_LOC = Loc.new(1250, 2075) # they moved it up to add Tag
POKEMON_INFO_APPRAISE_DISMISS_LOC = Loc.new(1030, 1850)
POKEMON_INFO_RENAME_LOC = Loc.new(720, 1210)
POKEMON_INFO_RENAME_DISMISS_LOC = Loc.new(720, 1120)
POKEMON_INFO_RENAME_OK_LOC = Loc.new(700, 1650)
POKEMON_INFO_SWIPE_START = Loc.new(1100, 1700)
POKEMON_INFO_SWIPE_END = Loc.new(400, 1700)
GBOARD_BACKSPACE = Loc.new(1330, 2560)

# Swipe gesture durations (in milliseconds)
POKEMON_INFO_SWIPE_DURATION = 200
DELETE_HOLD_DURATION = 60
DELETE_SWIPE_DURATION = 400

# Screenshot coordinates (in pixels) and colors (in RGBA hex) to check whether an operation succeeded
SCREENSHOT_POKELIST = SSLoc.new(Loc.new(760, 350), '#fbfffaff') # white background of list
SCREENSHOT_POKEMON_INFO = SSLoc.new(Loc.new(680, 2800), '#1c8796ff') # green background of close button
SCREENSHOT_POKEMON_MENU = SSLoc.new(Loc.new(100, 200), '#4ab483ff') # greenish gradient for menu background
SCREENSHOT_POKEMON_APPRAISE_INITIAL = SSLoc.new(Loc.new(100, 2600), '#ffffffff') # white background of textbox
SCREENSHOT_POKEMON_APPRAISE_BARS = SSLoc.new(Loc.new(660, 2130), '#ffffffff') # white background of appraisal bars
SCREENSHOT_POKEGENIE = SSLoc.new(Loc.new(10, 1010), '#eceff1ff') # gray background of Poke Genie IVision results
SCREENSHOT_RENAME = SSLoc.new(Loc.new(1150, 1620), '#43d0a5ff') # greenish background of OK button

# Keycode settings - see https://developer.android.com/reference/android/view/KeyEvent#constants_1 for a list
KEYCODE_BACKSPACE = 67
KEYCODE_PASTE = 279

# ADB settings
ADB_SEND_ENABLE = true # set to false to do a dry run
ADB_SCREENSHOT_VERIFY_ENABLE = true # set to false to assume everything succeeded and not check with screenshots (e.g. if you're watching...)
ADB_SCREENSHOT_VERIFY_RETRY_ATTEMPTS = 10
ADB_SCREENSHOT_VERIFY_RETRY_DELAY = 4

# Miscellaneous delays (in seconds)
DELAY_NO_VERIFY = 0.5
DELAY_VERIFY = 1
DELAY_SLOW = 2
DELAY_NONE = 0
DELAY_NEXT_POKEMON = 0
DELAY_IVISION = 1.5 # it's a verify delay, but IVision takes longer sometimes

# Miscellaneous constants
POKEMON_NAME_LENGTH = 12

def scale(loc, top)
  return Loc.new((PHONE_SIZE.x.to_f / REF_SIZE.x.to_f * loc.x.to_f).to_i, (PHONE_SIZE.y.to_f / REF_SIZE.y.to_f * loc.y.to_f).to_i + (top ? PHONE_TOP_MARGIN : 0))
end

def adb_verify_screenshot(ssloc, top = false)
  unless ADB_SCREENSHOT_VERIFY_ENABLE
    return
  end

  for attempt in 1..ADB_SCREENSHOT_VERIFY_RETRY_ATTEMPTS do
    pngname = "#{Dir.getwd}/temp.png"
    `adb exec-out screencap -p > #{pngname}`
    unless $?.success?
      throw 'adb_verify_screenshot failed - ' + $?.exitstatus
    end
    image = ChunkyPNG::Image.from_file(pngname)
    loc = scale(ssloc.loc, top)
    pixel = image.get_pixel(loc.x, loc.y)
    hex = ChunkyPNG::Color.to_hex(pixel)
    exp = ChunkyPNG::Color.from_hex(ssloc.color)

    File.delete(pngname)
    if pixel == exp
      return
    end

    delay = attempt <= 2 ? ADB_SCREENSHOT_VERIFY_RETRY_DELAY / 2 : ADB_SCREENSHOT_VERIFY_RETRY_DELAY
    puts ">> Screenshot validation failed - was #{hex} but expected #{ssloc.color}, waiting #{delay} sec, attempt #{attempt} of #{ADB_SCREENSHOT_VERIFY_RETRY_ATTEMPTS}"
    sleep(delay)
  end
  throw "Screenshot validation failure exceeded retry attempts. Maybe the game locked up or the servers went down? Start again manually."
end

def adb_tap(loc, wait, top = false)
  loc = scale(loc, top)
  puts("adb_tap #{loc.x} #{loc.y}")
  if ADB_SEND_ENABLE
    `adb shell input tap #{loc.x} #{loc.y}`
  end
  unless $?.success?
    throw 'adb_tap failed - ' + $?.exitstatus
  end
  sleep(ADB_SEND_ENABLE ? wait : 0)
end

def adb_swipe(start, finish, duration, wait, top = false)
  start = scale(start, top)
  finish = scale(finish, top)
  puts "adb_swipe #{start.x} #{start.y} #{finish.x} #{finish.y} #{duration}"
  if ADB_SEND_ENABLE
    `adb shell input swipe #{start.x} #{start.y} #{finish.x} #{finish.y} #{duration}`
  end
  unless $?.success?
    throw 'adb_swipe failed - ' + $?.exitstatus
  end
  sleep(ADB_SEND_ENABLE ? wait : 0)
end

def adb_backspace_swipe(loc, dx, hold_duration, swipe_duration, wait, top = false)
  loc = scale(loc, top)
  dx = scale(Loc.new(dx, 0), top).x # scale just the X coordinate
  puts "adb_backspace_swipe #{loc.x} #{loc.y}"
  if ADB_SEND_ENABLE
    `adb shell "input swipe #{loc.x} #{loc.y} #{loc.x} #{loc.y} #{hold_duration} && input swipe #{loc.x} #{loc.y} #{loc.x + dx} #{loc.y} #{swipe_duration}"`
  end
  unless $?.success?
    throw 'adb_backspace_swipe failed - ' + $?.exitstatus
  end
  sleep(ADB_SEND_ENABLE ? wait : 0)
end

def adb_key(keycode, wait)
  puts "adb_key #{keycode}"
  if ADB_SEND_ENABLE
    `adb shell input keyevent #{keycode}`
  end
  unless $?.success?
    throw 'adb_key failed - ' + $?.exitstatus
  end
  sleep(ADB_SEND_ENABLE ? wait : 0)
end

def adb_key_repeat(keycode, repeat, wait)
  puts "adb_key_repeat #{keycode} x#{repeat}"
  if repeat < 2 # no repeat
    adb_key(keycode, wait)
    return
  end

  if ADB_SEND_ENABLE
    adb_raw = "input keyevent #{keycode}"
    adb_cmd = adb_raw
    for i in 1..repeat
      adb_cmd = "#{adb_cmd} && #{adb_raw}"
    end
    `adb shell "#{adb_cmd}"`
  end
  unless $?.success?
    throw 'adb_key_repeat failed - ' + $?.exitstatus
  end
  sleep(ADB_SEND_ENABLE ? wait : 0)
end

row_even = true
adb_verify_screenshot(SCREENSHOT_POKEMON_INFO) # make sure we start out in Pokemon info
for i in 1..POKEMON_TO_PROCESS do
  puts "Scanning #{i} of #{POKEMON_TO_PROCESS}"

  # Open appraisal screen and get to the part that shows the bars
  adb_tap(POKEMON_INFO_MENU_LOC, DELAY_NO_VERIFY)
  adb_tap(POKEMON_INFO_APPRAISE_LOC, DELAY_NO_VERIFY)
  adb_tap(POKEMON_INFO_APPRAISE_DISMISS_LOC, DELAY_IVISION)

  # Wait for Poke Genie IVision to display
  adb_verify_screenshot(SCREENSHOT_POKEGENIE)

  # Dismiss the appraisal screen
  adb_tap(POKEMON_INFO_APPRAISE_DISMISS_LOC, DELAY_NO_VERIFY)

  # Open rename dialog
  adb_tap(POKEMON_INFO_RENAME_LOC, DELAY_NO_VERIFY, true) # this button is offset on some phones due to the dead zone at the top

  # Remove old name - switch to adb_key_repeat if adb_backspace_swipe is unreliable for you
  # adb_key_repeat(KEYCODE_BACKSPACE, POKEMON_NAME_LENGTH, DELAY_NONE)
  adb_backspace_swipe(GBOARD_BACKSPACE, -200, DELETE_HOLD_DURATION, DELETE_SWIPE_DURATION, DELAY_NONE)

  # Paste new name
  adb_key(KEYCODE_PASTE, DELAY_NONE)

  # Dismiss keyboard
  adb_tap(POKEMON_INFO_RENAME_DISMISS_LOC, DELAY_NO_VERIFY)

  # Rename Pokemon
  adb_tap(POKEMON_INFO_RENAME_OK_LOC, DELAY_VERIFY)
  adb_verify_screenshot(SCREENSHOT_POKEMON_INFO)

  # Swipe to next
  adb_swipe(POKEMON_INFO_SWIPE_START, POKEMON_INFO_SWIPE_END, POKEMON_INFO_SWIPE_DURATION, DELAY_NEXT_POKEMON)

  # Look like a human
  sleep(rand())
end