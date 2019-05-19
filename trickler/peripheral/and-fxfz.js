/**
 * Copyright (c) Ammolytics and contributors. All rights reserved.
 * Released under the MIT license. See LICENSE file in the project root for details.
 */
const events = require('events')

const SerialPort = require('serialport')
const Readline = require('@serialport/parser-readline')


const UNITS = {
  GRAINS: 0,
  GRAMS: 1,
}

const STATUS = {
  STABLE: 0,
  UNSTABLE: 1,
  OVERLOAD: 2,
  ERROR: 3,
  MODEL_NUMBER: 4,
  SERIAL_NUMBER: 5,
  ACKNOWLEDGE: 6,
}

const UNIT_MAP = {
  'GN': UNITS.GRAINS,
  'g': UNITS.GRAMS,
}

const STATUS_MAP = {
  'ST': STATUS.STABLE,
  // Counting mode
  'QT': STATUS.STABLE,
  'US': STATUS.UNSTABLE,
  'OL': STATUS.OVERLOAD,
  'EC': STATUS.ERROR,
  'AK': STATUS.ACKNOWLEDGE,
  'TN': STATUS.MODEL_NUMBER,
  'SN': STATUS.SERIAL_NUMBER,
}

const ERROR_CODES = {
  'E00': 'Communications error',
  'E01': 'Undefined command error',
  'E02': 'Not ready',
  'E03': 'Timeout error',
  'E04': 'Excess characters error',
  'E06': 'Format error',
  'E07': 'Parameter setting error',
  'E11': 'Stability error',
  'E17': 'Internal mass error',
  'E20': 'Calibration weight error: The calibration weight is too heavy',
  'E21': 'Calibration weight error: The calibration weight is too light',
}

const COMMAND_MAP = {
  ID: '?ID\r\n',
  SERIAL_NUMBER: '?SN\r\n',
  MODEL_NUMBER: '?TN\r\n',
  TARE_WEIGHT: '?PT\r\n',
  CAL_BTN: 'CAL\r\n',
  OFF_BTN: 'OFF\r\n',
  ON_BTN: 'ON\r\n',
  ONOFF_BTN: 'P\r\n',
  PRINT_BTN: 'PRT\r\n',
  REZERO_BTN: 'R\r\n',
  SAMPLE_BTN: 'SMP\r\n',
  MODE_BTN: 'U\r\n',
}


// TODO: Emit 'ready' when signals received from scale.

class Scale extends events.EventEmitter {
  constructor (opts) {
    super()
    opts = (typeof opts === 'object') ? opts : {}
    this.BAUD = Number(opts.baud) || 19200
    this.DEV_PATH = opts.device || '/dev/ttyUSB0'
    this.encoding = 'ascii'
    this.delimiter = '\r\n'

    this._weight = 0.0
    this._stable = false
    this._unit = ''
    this._serial = ''
    this._model = ''

    this.parser = new Readline({
      delimiter: this.delimiter,
      encoding: this.encoding
    })

    // Create mock binding if env MOCK is set.
    if (process.env.MOCK) {
      console.log('Using Mock interface')
      const MockScale = require('./mock-scale')
      SerialPort.Binding = MockScale
      // Create a port and enable the echo and recording.
      MockScale.createPort(this.DEV_PATH, { echo: true, record: true })
    }

    var portOpts = {
        autoOpen: false,
        baudRate: this.BAUD,
      }

    this.port = new SerialPort(this.DEV_PATH, portOpts, this._error)

    this.port.on('error', err => {
      console.error(`Serial port error: ${err.message}`)
      this.emit('error', err)
    })
    this.port.on('open', () => {
      console.log(`Serial port open`)
      this.emit('open')
    })
    this.port.on('close', () => {
      console.log(`Serial port close`)
      this.emit('close')
    })

    this.port.pipe(this.parser)
    this.parser.on('data', line => { this.lineParser(line) })
  }

  // Error handler/logger.
  _error (err) {
    if (err) {
      console.error(err)
    }
  }

  open (cb) {
    this.port.open(cb)
  }

  close (cb) {
    this.port.close(cb)
  }

  set weight (value) {
    value = Number(value)
    if (this._weight !== value) {
      this._weight = value
      this.emit('weight', this._weight)
    }
  }

  get weight () {
    return this._weight
  }

  set stable (value) {
    if (this._stable !== value) {
      this._stable = value
      this.emit('stable', this._stable)
      if (this._stable === true) {
        this.lastStable = new Date()
      }
    }
  }

  get stable () {
    return this._stable
  }

  get stableTime () {
    return new Date() - this.lastStable
  }

  set unit (value) {
    if (this._unit !== value) {
      this._unit = value
      this.emit('unit', this._unit)
    }
  }

  get unit () {
    return this._unit
  }

  set model (value) {
    this._model = value
    this.emit('model', this._model)
  }

  get model () {
    return this._model
  }

  set serial (value) {
    this._serial = value
    this.emit('serial', this._serial)
  }

  get serial () {
    return this._serial
  }

  lineParser (rawLine) {
    var now = new Date()
    var line = rawLine.trim()
    var statusStr = line.substr(0, 2)

    this.emit('data', line)

    if (process.env.DEBUG) {
      console.log(`${now} ${line}`)
    }

    switch (STATUS_MAP[statusStr]) {
      case STATUS.ACKNOWLEDGE:
        console.log('Command acknowledged')
        break
      case STATUS.ERROR:
        var errCode = line.substr(3, 3)
        var errMsg = ERROR_CODES[errCode]
        this._error(`Error code: ${errCode}, message: ${errMsg}, line: ${line}`)
        break
      case STATUS.MODEL_NUMBER:
        this.model = line.substr(3)
        break
      case STATUS.SERIAL_NUMBER:
        this.serial = line.substr(3)
        break
      case STATUS.STABLE:
      case STATUS.UNSTABLE:
        var rawWeight = line.substr(3, 9)
        var rawUnit = line.substr(12, 3)
        this.weight = rawWeight
        this.unit = UNIT_MAP[rawUnit]
        this.stable = STATUS_MAP[statusStr] === STATUS.STABLE
        break
      default:
        console.log(`UNHANDLED MESSAGE: ${line}`)
        break
    }
  }

  getModelNumber () {
    console.log('WRITE: Requesting model number...')
    this.port.write(COMMAND_MAP.MODEL_NUMBER, this.encoding, this._error)
  }

  getSerialNumber () {
    console.log('WRITE: Requesting serial number...')
    this.port.write(COMMAND_MAP.SERIAL_NUMBER, this.encoding, this._error)
  }

  pressMode () {
    console.log('WRITE: Pressing Mode button to change unit...')
    this.port.write(COMMAND_MAP.MODE_BTN, this.encoding, this._error)
  }

  reZero () {
    console.log('WRITE: Pressing ReZero button...')
    this.port.write(COMMAND_MAP.REZERO_BTN, this.encoding, this._error)
  }
}


module.exports.Scale = Scale