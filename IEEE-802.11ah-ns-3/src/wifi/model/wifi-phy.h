/* -*- Mode:C++; c-file-style:"gnu"; indent-tabs-mode:nil; -*- */
/*
 * Copyright (c) 2005,2006 INRIA
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation;
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 * Author: Mathieu Lacage <mathieu.lacage@sophia.inria.fr>
 */

#ifndef WIFI_PHY_H
#define WIFI_PHY_H

#include <stdint.h>
#include "ns3/callback.h"
#include "ns3/packet.h"
#include "ns3/object.h"
#include "ns3/nstime.h"
#include "ns3/ptr.h"
#include "wifi-mode.h"
#include "wifi-preamble.h"
#include "wifi-phy-standard.h"
#include "ns3/traced-callback.h"
#include "wifi-tx-vector.h"
#include "drop-reason.h"

namespace ns3 {

class WifiChannel;
class NetDevice;

/**
 * \brief receive notifications about phy events.
 */
class WifiPhyListener
{
public:
  virtual ~WifiPhyListener ();

  /**
   * \param duration the expected duration of the packet reception.
   *
   * We have received the first bit of a packet. We decided
   * that we could synchronize on this packet. It does not mean
   * we will be able to successfully receive completely the
   * whole packet. It means that we will report a BUSY status until
   * one of the following happens:
   *   - NotifyRxEndOk
   *   - NotifyRxEndError
   *   - NotifyTxStart
   */
  virtual void NotifyRxStart (Time duration) = 0;
  /**
   * We have received the last bit of a packet for which
   * NotifyRxStart was invoked first and, the packet has
   * been successfully received.
   */
  virtual void NotifyRxEndOk (void) = 0;
  /**
   * We have received the last bit of a packet for which
   * NotifyRxStart was invoked first and, the packet has
   * _not_ been successfully received.
   */
  virtual void NotifyRxEndError (void) = 0;
  /**
   * \param duration the expected transmission duration.
   * \param txPowerDbm the nominal tx power in dBm
   *
   * We are about to send the first bit of the packet.
   * We do not send any event to notify the end of
   * transmission. Listeners should assume that the
   * channel implicitely reverts to the idle state
   * unless they have received a cca busy report.
   */
  virtual void NotifyTxStart (Time duration, double txPowerDbm) = 0;
  /**
   * \param duration the expected busy duration.
   *
   * This method does not really report a real state
   * change as opposed to the other methods in this class.
   * It merely reports that, unless the medium is reported
   * busy through NotifyTxStart or NotifyRxStart/End,
   * it will be busy as defined by the currently selected
   * CCA mode.
   *
   * Typical client code which wants to have a clear picture
   * of the CCA state will need to keep track of the time at
   * which the last NotifyCcaBusyStart method is called and
   * what duration it reported.
   */
  virtual void NotifyMaybeCcaBusyStart (Time duration) = 0;
  /**
   * \param duration the expected channel switching duration.
   *
   * We do not send any event to notify the end of
   * channel switching. Listeners should assume that the
   * channel implicitely reverts to the idle or busy states.
   */
  virtual void NotifySwitchingStart (Time duration) = 0;
  /**
   * Notify listeners that we went to sleep
   */
  virtual void NotifySleep (void) = 0;
  /**
   * Notify listeners that we woke up
   */
  virtual void NotifyWakeup (void) = 0;
};


/**
 * \brief 802.11 PHY layer model
 * \ingroup wifi
 *
 */
class WifiPhy : public Object
{
public:
  /**
   * The state of the PHY layer.
   */
  enum State
  {
    /**
     * The PHY layer is IDLE.
     */
    IDLE,
    /**
     * The PHY layer has sense the medium busy through the CCA mechanism
     */
    CCA_BUSY,
    /**
     * The PHY layer is sending a packet.
     */
    TX,
    /**
     * The PHY layer is receiving a packet.
     */
    RX,
    /**
     * The PHY layer is switching to other channel.
     */
    SWITCHING,
    /**
     * The PHY layer is sleeping.
     */
    SLEEP
  };

  /**
   * arg1: packet received successfully
   * arg2: snr of packet
   * arg3: TXVECTOR of packet
   * arg4: type of preamble used for packet.
   */
  typedef Callback<void, Ptr<Packet>, double, WifiTxVector, enum WifiPreamble> RxOkCallback;
  /**
   * arg1: packet received unsuccessfully
   * arg2: snr of packet
   */
  typedef Callback<void, Ptr<const Packet>, double> RxErrorCallback;

  typedef void (* PhyRxDropWithReasonCallback)
                (Ptr<const Packet> packet, DropReason reason);

  typedef void (* PhyTxDropWithReasonCallback)
                  (Ptr<const Packet> packet, DropReason reason);
  static TypeId GetTypeId (void);

  WifiPhy ();
  virtual ~WifiPhy ();

  /**
   * Return the minimum available transmission power level (dBm).
   *
   * \return the minimum available transmission power level in dBm
   */
  virtual double GetTxPowerStart (void) const = 0;
  /**
   * Return the maximum available transmission power level (dBm).
   *
   * \return the maximum available transmission power level in dBm
   */
  virtual double GetTxPowerEnd (void) const = 0;
  /**
   * \return the number of tx power levels available for this PHY.
   */
  virtual uint32_t GetNTxPower (void) const = 0;

  /**
   * \param callback the callback to invoke
   *        upon successful packet reception.
   */
  virtual void SetReceiveOkCallback (RxOkCallback callback) = 0;
  /**
   * \param callback the callback to invoke
   *        upon erroneous packet reception.
   */
  virtual void SetReceiveErrorCallback (RxErrorCallback callback) = 0;

  /**
   * \param packet the packet to send
   * \param txvector the txvector that has tx parameters such as mode, the transmission mode to use to send
   *        this packet, and txPowerLevel, a power level to use to send this packet. The real transmission
   *        power is calculated as txPowerMin + txPowerLevel * (txPowerMax - txPowerMin) / nTxLevels
   * \param preamble the type of preamble to use to send this packet.
   * \param packetType the type of the packet 0 is not A-MPDU, 1 is a MPDU that is part of an A-MPDU and 2 is the last MPDU in an A-MPDU
   */
  virtual void SendPacket (Ptr<const Packet> packet, WifiTxVector txvector, enum WifiPreamble preamble, uint8_t packetType) = 0;

  /**
   * \param listener the new listener
   *
   * Add the input listener to the list of objects to be notified of
   * PHY-level events.
   */
  virtual void RegisterListener (WifiPhyListener *listener) = 0;
  /**
   * \param listener the listener to be unregistered
   *
   * Remove the input listener from the list of objects to be notified of
   * PHY-level events.
   */
  virtual void UnregisterListener (WifiPhyListener *listener) = 0;

  /**
   * Put in sleep mode.
   */
  virtual void SetSleepMode (void) = 0;
  /**
   * Resume from sleep mode.
   */
  virtual void ResumeFromSleep (void) = 0;

  /**
   * \return true of the current state of the PHY layer is WifiPhy::IDLE, false otherwise.
   */
  virtual bool IsStateIdle (void) = 0;
  /**
   * \return true of the current state of the PHY layer is WifiPhy::CCA_BUSY, false otherwise.
   */
  virtual bool IsStateCcaBusy (void) = 0;
  /**
   * \return true of the current state of the PHY layer is not WifiPhy::IDLE, false otherwise.
   */
  virtual bool IsStateBusy (void) = 0;
  /**
   * \return true of the current state of the PHY layer is WifiPhy::RX, false otherwise.
   */
  virtual bool IsStateRx (void) = 0;
  /**
   * \return true of the current state of the PHY layer is WifiPhy::TX, false otherwise.
   */
  virtual bool IsStateTx (void) = 0;
  /**
   * \return true of the current state of the PHY layer is WifiPhy::SWITCHING, false otherwise.
   */
  virtual bool IsStateSwitching (void) = 0;
  /**
   * \return true if the current state of the PHY layer is WifiPhy::SLEEP, false otherwise.
   */
  virtual bool IsStateSleep (void) = 0;
  /**
   * \return the amount of time since the current state has started.
   */
  virtual Time GetStateDuration (void) = 0;
  /**
   * \return the predicted delay until this PHY can become WifiPhy::IDLE.
   *
   * The PHY will never become WifiPhy::IDLE _before_ the delay returned by
   * this method but it could become really idle later.
   */
  virtual Time GetDelayUntilIdle (void) = 0;

  /**
   * Return the start time of the last received packet.
   *
   * \return the start time of the last received packet
   */
  virtual Time GetLastRxStartTime (void) const = 0;

  /**
   * \param size the number of bytes in the packet to send
   * \param txvector the transmission parameters used for this packet
   * \param preamble the type of preamble to use for this packet.
   * \param frequency the channel center frequency (MHz)
   * \param packetType the type of the packet 0 is not A-MPDU, 1 is a MPDU that is part of an A-MPDU and 2 is the last MPDU in an A-MPDU
   * \param incFlag this flag is used to indicate that the static variables need to be update or not. This function is called a couple of times for the same packet so static variables should not be increased each time.
   *
   * \return the total amount of time this PHY will stay busy for the transmission of these bytes.
   */
  Time CalculateTxDuration (uint32_t size, WifiTxVector txvector, enum WifiPreamble preamble, double frequency, uint8_t packetType, uint8_t incFlag);

  /**
   * \param txvector the transmission parameters used for this packet
   * \param preamble the type of preamble to use for this packet.
   *
   * \return the total amount of time this PHY will stay busy for the transmission of the PLCP preamble and PLCP header.
   */
  Time CalculatePlcpPreambleAndHeaderDuration (WifiTxVector txvector, enum WifiPreamble preamble);

  /**
   * \param preamble the type of preamble
   * \param txvector the transmission parameters used for this packet
   *
   * \return the training symbol duration
   */
  static Time GetPlcpHtTrainingSymbolDuration (WifiPreamble preamble, WifiTxVector txvector);
  /**
   * \param payloadMode the WifiMode use for the transmission of the payload
   * \param preamble the type of preamble
   *
   * \return the WifiMode used for the transmission of the HT-SIG and the HT training fields
   *         in Mixed Format and greenfield format PLCP header
   */
  static WifiMode GetHTPlcpHeaderMode (WifiMode payloadMode, WifiPreamble preamble);
  /**
   * \param preamble the type of preamble
   *
   * \return the duration of the HT-SIG in Mixed Format and greenfield format PLCP header
   */
  static Time GetPlcpHtSigHeaderDuration (WifiPreamble preamble);
  /**
   * \param payloadMode the WifiMode use for the transmission of the payload
   * \param preamble the type of preamble
   *
   * \return the WifiMode used for the transmission of the PLCP header
   */
  static WifiMode GetPlcpHeaderMode (WifiMode payloadMode, WifiPreamble preamble);
  /**
   * \param payloadMode the WifiMode use for the transmission of the payload
   * \param preamble the type of preamble
   *
   * \return the duration of the PLCP header
   */
  static Time GetPlcpHeaderDuration (WifiMode payloadMode, WifiPreamble preamble);
  /**
   * \param payloadMode the WifiMode use for the transmission of the payload
   * \param preamble the type of preamble
   *
   * \return the duration of the PLCP preamble
   */
  static Time GetPlcpPreambleDuration (WifiMode payloadMode, WifiPreamble preamble);
  /**
   * \param preamble the type of preamble
   * \param txvector the transmission parameters used for this packet
   *
   * \return S1G training symbol duration
   */
  static Time GetPlcpS1gTrainingSymbolDuration (WifiPreamble preamble, WifiTxVector txvector);
  /**
   * \param preamble the type of preamble
   * \param txvector the transmission parameters used for this packet
   *
   * \return S1G-A  symbol duration
   */
  static Time GetPlcpSigADuration (WifiPreamble preamble);
  /**
   * \param preamble the type of preamble
   * \param txvector the transmission parameters used for this packet
   *
   * \return S1G-B  symbol duration
   */
  static Time GetPlcpSigBDuration (WifiPreamble preamble);
  /**
   * \param preamble the type of preamble
   * \param txvector the transmission parameters used for this packet
   *
   * \return Plcp Training  symbol duration
   */
  static Time GetPlcpTrainingSymbolDuration (WifiPreamble preamble, WifiTxVector txvector);
  /**
   * \param size the number of bytes in the packet to send
   * \param txvector the transmission parameters used for this packet
   * \param preamble the type of preamble to use for this packet
   * \param frequency the channel center frequency (MHz)
   * \param packetType the type of the packet (0 is not A-MPDU, 1 is a MPDU that is part of an A-MPDU and 2 is the last MPDU in an A-MPDU)
   * \param incFlag this flag is used to indicate that the static variables need to be update or not. This function is called a couple of times for the same packet so static variables should not be increased each time
   *
   * \return the duration of the payload
   */
  Time GetPayloadDuration (uint32_t size, WifiTxVector txvector, WifiPreamble preamble, double frequency, uint8_t packetType, uint8_t incFlag);

  /**
   * The WifiPhy::GetNModes() and WifiPhy::GetMode() methods are used
   * (e.g., by a WifiRemoteStationManager) to determine the set of
   * transmission/reception modes that this WifiPhy(-derived class)
   * can support - a set of WifiMode objects which we call the
   * DeviceRateSet, and which is stored as WifiPhy::m_deviceRateSet.
   *
   * It is important to note that the DeviceRateSet is a superset (not
   * necessarily proper) of the OperationalRateSet (which is
   * logically, if not actually, a property of the associated
   * WifiRemoteStationManager), which itself is a superset (again, not
   * necessarily proper) of the BSSBasicRateSet.
   *
   * \return the number of transmission modes supported by this PHY.
   *
   * \sa WifiPhy::GetMode()
   */
  virtual uint32_t GetNModes (void) const = 0;
  /**
   * The WifiPhy::GetNModes() and WifiPhy::GetMode() methods are used
   * (e.g., by a WifiRemoteStationManager) to determine the set of
   * transmission/reception modes that this WifiPhy(-derived class)
   * can support - a set of WifiMode objects which we call the
   * DeviceRateSet, and which is stored as WifiPhy::m_deviceRateSet.
   *
   * It is important to note that the DeviceRateSet is a superset (not
   * necessarily proper) of the OperationalRateSet (which is
   * logically, if not actually, a property of the associated
   * WifiRemoteStationManager), which itself is a superset (again, not
   * necessarily proper) of the BSSBasicRateSet.
   *
   * \param mode index in array of supported modes
   *
   * \return the mode whose index is specified.
   *
   * \sa WifiPhy::GetNModes()
   */
  virtual WifiMode GetMode (uint32_t mode) const = 0;
  /**
   * Check if the given WifiMode is supported by the PHY.
   *
   * \param mode the wifi mode to check
   *
   * \return true if the given mode is supported,
   *         false otherwise
   */
  virtual bool IsModeSupported (WifiMode mode) const = 0;

  /**
   * \param txMode the transmission mode
   * \param ber the probability of bit error rate
   *
   * \return the minimum snr which is required to achieve
   *          the requested ber for the specified transmission mode. (W/W)
   */
  virtual double CalculateSnr (WifiMode txMode, double ber) const = 0;

  /**
  * The WifiPhy::NBssMembershipSelectors() method is used
  * (e.g., by a WifiRemoteStationManager) to determine the set of
  * transmission/reception modes that this WifiPhy(-derived class)
  * can support - a set of WifiMode objects which we call the
  * BssMembershipSelectorSet, and which is stored as WifiPhy::m_bssMembershipSelectorSet.
  *
  * \return the memebership selector whose index is specified.
  */
  virtual uint32_t GetNBssMembershipSelectors (void) const = 0;
  /**
  * The WifiPhy::BssMembershipSelector() method is used
  * (e.g., by a WifiRemoteStationManager) to determine the set of
  * transmission/reception modes that this WifiPhy(-derived class)
  * can support - a set of WifiMode objects which we call the
  * BssMembershipSelectorSet, and which is stored as WifiPhy::m_bssMembershipSelectorSet.
  *
  * \param selector index in array of supported memberships
  *
  * \return the memebership selector whose index is specified.
  */
  virtual uint32_t GetBssMembershipSelector (uint32_t selector) const = 0;
  /**
   * The WifiPhy::GetMembershipSelectorModes() method is used
   * (e.g., by a WifiRemoteStationManager) to determine the set of
   * transmission/reception modes that this WifiPhy(-derived class)
   * can support - a set of WifiMode objects which we call the
   * BssMembershipSelectorSet, and which is stored as WifiPhy::m_bssMembershipSelectorSet.
   *
   * \param selector index in array of supported memberships
   *
   * \return a WifiModeList that contains the WifiModes associrated with the selected index.
   *
   * \sa WifiPhy::GetMembershipSelectorModes()
   */
  virtual WifiModeList GetMembershipSelectorModes (uint32_t selector) = 0;
  /**
   * The WifiPhy::GetNMcs() method is used
   * (e.g., by a WifiRemoteStationManager) to determine the set of
   * transmission/reception MCS indexes that this WifiPhy(-derived class)
   * can support - a set of MCS indexes which we call the
   * DeviceMcsSet, and which is stored as WifiPhy::m_deviceMcsSet.
   *
   * \return the MCS index whose index is specified.
   */
  virtual uint8_t GetNMcs (void) const = 0;
  /**
   * The WifiPhy::GetMcs() method is used
   * (e.g., by a WifiRemoteStationManager) to determine the set of
   * transmission/reception MCS indexes that this WifiPhy(-derived class)
   * can support - a set of MCS indexes which we call the
   * DeviceMcsSet, and which is stored as WifiPhy::m_deviceMcsSet.
   *
   * \param mcs index in array of supported MCS
   *
   * \return the MCS index whose index is specified.
   */
  virtual uint8_t GetMcs (uint8_t mcs) const = 0;

  /**
  * For a given WifiMode finds the corresponding MCS value and returns it
  * as defined in the IEEE 802.11n standard
  *
  * \param mode the WifiMode
  *
  * \return the MCS number that corresponds to the given WifiMode
  */
  virtual uint32_t WifiModeToMcs (WifiMode mode) = 0;
  /**
   * For a given MCS finds the corresponding WifiMode and returns it
   * as defined in the IEEE 802.11n standard.
   *
   * \param mcs the MCS number
   *
   * \return the WifiMode that corresponds to the given MCS number
   */
  virtual WifiMode McsToWifiMode (uint8_t mcs) = 0;

  /**
   * \brief Set channel number.
   *
   * Channel center frequency = Channel starting frequency + 5 MHz * (nch - 1)
   *
   * where Starting channel frequency is standard-dependent, see SetStandard()
   * as defined in (Section 18.3.8.4.2 "Channel numbering"; IEEE Std 802.11-2012).
   *
   * \param id the channel number
   */
  virtual void SetChannelNumber (uint16_t id) = 0;
  /**
   * Return current channel number.
   *
   * \return the current channel number
   */
  virtual uint16_t GetChannelNumber (void) const = 0;
  /**
   * \return the required time for channel switch operation of this WifiPhy
   */
  virtual Time GetChannelSwitchDelay (void) const = 0;

  /**
   * Configure the PHY-level parameters for different Wi-Fi standard.
   *
   * \param standard the Wi-Fi standard
   */
  virtual void ConfigureStandard (enum WifiPhyStandard standard) = 0;

  /**
   * Return the WifiChannel this WifiPhy is connected to.
   *
   * \return the WifiChannel this WifiPhy is connected to
   */
  virtual Ptr<WifiChannel> GetChannel (void) const = 0;

  /**
   * Return a WifiMode for DSSS at 1Mbps.
   *
   * \return a WifiMode for DSSS at 1Mbps
   */
  static WifiMode GetDsssRate1Mbps ();
  /**
   * Return a WifiMode for DSSS at 2Mbps.
   *
   * \return a WifiMode for DSSS at 2Mbps
   */
  static WifiMode GetDsssRate2Mbps ();
  /**
   * Return a WifiMode for DSSS at 5.5Mbps.
   *
   * \return a WifiMode for DSSS at 5.5Mbps
   */
  static WifiMode GetDsssRate5_5Mbps ();
  /**
   * Return a WifiMode for DSSS at 11Mbps.
   *
   * \return a WifiMode for DSSS at 11Mbps
   */
  static WifiMode GetDsssRate11Mbps ();
  /**
   * Return a WifiMode for ERP-OFDM at 6Mbps.
   *
   * \return a WifiMode for ERP-OFDM at 6Mbps
   */
  static WifiMode GetErpOfdmRate6Mbps ();
  /**
   * Return a WifiMode for ERP-OFDM at 9Mbps.
   *
   * \return a WifiMode for ERP-OFDM at 9Mbps
   */
  static WifiMode GetErpOfdmRate9Mbps ();
  /**
   * Return a WifiMode for ERP-OFDM at 12Mbps.
   *
   * \return a WifiMode for ERP-OFDM at 12Mbps
   */
  static WifiMode GetErpOfdmRate12Mbps ();
  /**
   * Return a WifiMode for ERP-OFDM at 18Mbps.
   *
   * \return a WifiMode for ERP-OFDM at 18Mbps
   */
  static WifiMode GetErpOfdmRate18Mbps ();
  /**
   * Return a WifiMode for ERP-OFDM at 24Mbps.
   *
   * \return a WifiMode for ERP-OFDM at 24Mbps
   */
  static WifiMode GetErpOfdmRate24Mbps ();
  /**
   * Return a WifiMode for ERP-OFDM at 36Mbps.
   *
   * \return a WifiMode for ERP-OFDM at 36Mbps
   */
  static WifiMode GetErpOfdmRate36Mbps ();
  /**
   * Return a WifiMode for ERP-OFDM at 48Mbps.
   *
   * \return a WifiMode for ERP-OFDM at 48Mbps
   */
  static WifiMode GetErpOfdmRate48Mbps ();
  /**
   * Return a WifiMode for ERP-OFDM at 54Mbps.
   *
   * \return a WifiMode for ERP-OFDM at 54Mbps
   */
  static WifiMode GetErpOfdmRate54Mbps ();
  /**
   * Return a WifiMode for OFDM at 6Mbps.
   *
   * \return a WifiMode for OFDM at 6Mbps
   */
  static WifiMode GetOfdmRate6Mbps ();
  /**
   * Return a WifiMode for OFDM at 9Mbps.
   *
   * \return a WifiMode for OFDM at 9Mbps
   */
  static WifiMode GetOfdmRate9Mbps ();
  /**
   * Return a WifiMode for OFDM at 12Mbps.
   *
   * \return a WifiMode for OFDM at 12Mbps
   */
  static WifiMode GetOfdmRate12Mbps ();
  /**
   * Return a WifiMode for OFDM at 18Mbps.
   *
   * \return a WifiMode for OFDM at 18Mbps
   */
  static WifiMode GetOfdmRate18Mbps ();
  /**
   * Return a WifiMode for OFDM at 24Mbps.
   *
   * \return a WifiMode for OFDM at 24Mbps
   */
  static WifiMode GetOfdmRate24Mbps ();
  /**
   * Return a WifiMode for OFDM at 36Mbps.
   *
   * \return a WifiMode for OFDM at 36Mbps
   */
  static WifiMode GetOfdmRate36Mbps ();
  /**
   * Return a WifiMode for OFDM at 48Mbps.
   *
   * \return a WifiMode for OFDM at 48Mbps
   */
  static WifiMode GetOfdmRate48Mbps ();
  /**
   * Return a WifiMode for OFDM at 54Mbps.
   *
   * \return a WifiMode for OFDM at 54Mbps
   */
  static WifiMode GetOfdmRate54Mbps ();
  /**
   * Return a WifiMode for OFDM at 3Mbps with 10MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 3Mbps with 10MHz channel spacing
   */
  static WifiMode GetOfdmRate3MbpsBW10MHz ();
  /**
   * Return a WifiMode for OFDM at 4.5Mbps with 10MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 4.5Mbps with 10MHz channel spacing
   */
  static WifiMode GetOfdmRate4_5MbpsBW10MHz ();
  /**
   * Return a WifiMode for OFDM at 6Mbps with 10MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 6Mbps with 10MHz channel spacing
   */
  static WifiMode GetOfdmRate6MbpsBW10MHz ();
  /**
   * Return a WifiMode for OFDM at 9Mbps with 10MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 9Mbps with 10MHz channel spacing
   */
  static WifiMode GetOfdmRate9MbpsBW10MHz ();
  /**
   * Return a WifiMode for OFDM at 12Mbps with 10MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 12Mbps with 10MHz channel spacing
   */
  static WifiMode GetOfdmRate12MbpsBW10MHz ();
  /**
   * Return a WifiMode for OFDM at 18Mbps with 10MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 18Mbps with 10MHz channel spacing
   */
  static WifiMode GetOfdmRate18MbpsBW10MHz ();
  /**
   * Return a WifiMode for OFDM at 24Mbps with 10MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 24Mbps with 10MHz channel spacing
   */
  static WifiMode GetOfdmRate24MbpsBW10MHz ();
  /**
   * Return a WifiMode for OFDM at 27Mbps with 10MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 27Mbps with 10MHz channel spacing
   */
  static WifiMode GetOfdmRate27MbpsBW10MHz ();
  /**
   * Return a WifiMode for OFDM at 1.5Mbps with 5MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 1.5Mbps with 5MHz channel spacing
   */
  static WifiMode GetOfdmRate1_5MbpsBW5MHz ();
  /**
   * Return a WifiMode for OFDM at 2.25Mbps with 5MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 2.25Mbps with 5MHz channel spacing
   */
  static WifiMode GetOfdmRate2_25MbpsBW5MHz ();
  /**
   * Return a WifiMode for OFDM at 3Mbps with 5MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 3Mbps with 5MHz channel spacing
   */
  static WifiMode GetOfdmRate3MbpsBW5MHz ();
  /**
   * Return a WifiMode for OFDM at 4.5Mbps with 5MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 4.5Mbps with 5MHz channel spacing
   */
  static WifiMode GetOfdmRate4_5MbpsBW5MHz ();
  /**
   * Return a WifiMode for OFDM at 6Mbps with 5MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 6Mbps with 5MHz channel spacing
   */
  static WifiMode GetOfdmRate6MbpsBW5MHz ();
  /**
   * Return a WifiMode for OFDM at 9Mbps with 5MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 9Mbps with 5MHz channel spacing
   */
  static WifiMode GetOfdmRate9MbpsBW5MHz ();
  /**
   * Return a WifiMode for OFDM at 12Mbps with 5MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 12Mbps with 5MHz channel spacing
   */
  static WifiMode GetOfdmRate12MbpsBW5MHz ();
  /**
   * Return a WifiMode for OFDM at 13.5Mbps with 5MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 13.5Mbps with 5MHz channel spacing
   */
  static WifiMode GetOfdmRate13_5MbpsBW5MHz ();
  /**
   * Return a WifiMode for OFDM at 6.5Mbps with 20MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 6.5Mbps with 20MHz channel spacing
   */
  static WifiMode GetOfdmRate6_5MbpsBW20MHz ();
  /**
   * Return a WifiMode for OFDM at 13Mbps with 20MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 13Mbps with 20MHz channel spacing
   */
  static WifiMode GetOfdmRate13MbpsBW20MHz ();
  /**
   * Return a WifiMode for OFDM at 19.5Mbps with 20MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 19.5Mbps with 20MHz channel spacing
   */
  static WifiMode GetOfdmRate19_5MbpsBW20MHz ();
  /**
   * Return a WifiMode for OFDM at 26Mbps with 20MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 26Mbps with 20MHz channel spacing
   */
  static WifiMode GetOfdmRate26MbpsBW20MHz ();
  /**
   * Return a WifiMode for OFDM at 39Mbps with 20MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 39Mbps with 20MHz channel spacing
   */
  static WifiMode GetOfdmRate39MbpsBW20MHz ();
  /**
   * Return a WifiMode for OFDM at 52Mbps with 20MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 52Mbps with 20MHz channel spacing
   */
  static WifiMode GetOfdmRate52MbpsBW20MHz ();
  /**
   * Return a WifiMode for OFDM at 58.5Mbps with 20MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 58.5Mbps with 20MHz channel spacing
   */
  static WifiMode GetOfdmRate58_5MbpsBW20MHz ();
  /**
   * Return a WifiMode for OFDM at 65Mbps with 20MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 65Mbps with 20MHz channel spacing
   */
  static WifiMode GetOfdmRate65MbpsBW20MHz ();
  /**
   * Return a WifiMode for OFDM at 13.5Mbps with 40MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 13.5Mbps with 40MHz channel spacing
   */
  static WifiMode GetOfdmRate13_5MbpsBW40MHz ();
  /**
   * Return a WifiMode for OFDM at 27Mbps with 40MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 27Mbps with 40MHz channel spacing
   */
  static WifiMode GetOfdmRate27MbpsBW40MHz ();
  /**
   * Return a WifiMode for OFDM at 40.5Mbps with 40MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 40.5Mbps with 40MHz channel spacing
   */
  static WifiMode GetOfdmRate40_5MbpsBW40MHz ();
  /**
   * Return a WifiMode for OFDM at 54Mbps with 40MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 54Mbps with 40MHz channel spacing
   */
  static WifiMode GetOfdmRate54MbpsBW40MHz ();
  /**
   * Return a WifiMode for OFDM at 81Mbps with 40MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 81Mbps with 40MHz channel spacing
   */
  static WifiMode GetOfdmRate81MbpsBW40MHz ();
  /**
   * Return a WifiMode for OFDM at 108Mbps with 40MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 108Mbps with 40MHz channel spacing
   */
  static WifiMode GetOfdmRate108MbpsBW40MHz ();
  /**
   * Return a WifiMode for OFDM at 121.5Mbps with 40MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 121.5Mbps with 40MHz channel spacing
   */
  static WifiMode GetOfdmRate121_5MbpsBW40MHz ();
  /**
   * Return a WifiMode for OFDM at 135Mbps with 40MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 135Mbps with 40MHz channel spacing
   */
  static WifiMode GetOfdmRate135MbpsBW40MHz ();
  /**
   * Return a WifiMode for OFDM at 7.2Mbps with 20MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 7.2Mbps with 20MHz channel spacing
   */
  static WifiMode GetOfdmRate7_2MbpsBW20MHz ();
  /**
   * Return a WifiMode for OFDM at 14.4Mbps with 20MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 14.4Mbps with 20MHz channel spacing
   */
  static WifiMode GetOfdmRate14_4MbpsBW20MHz ();
  /**
   * Return a WifiMode for OFDM at 21.7Mbps with 20MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 21.7Mbps with 20MHz channel spacing
   */
  static WifiMode GetOfdmRate21_7MbpsBW20MHz ();
  /**
   * Return a WifiMode for OFDM at 28.9Mbps with 20MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 28.9Mbps with 20MHz channel spacing
   */
  static WifiMode GetOfdmRate28_9MbpsBW20MHz ();
  /**
   * Return a WifiMode for OFDM at 43.3Mbps with 20MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 43.3Mbps with 20MHz channel spacing
   */
  static WifiMode GetOfdmRate43_3MbpsBW20MHz ();
  /**
   * Return a WifiMode for OFDM at 57.8Mbps with 20MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 57.8Mbps with 20MHz channel spacing
   */
  static WifiMode GetOfdmRate57_8MbpsBW20MHz ();
  /**
   * Return a WifiMode for OFDM at 65Mbps with 20MHz channel spacing.
   * The rate supports short guard interval.
   *
   * \return a WifiMode for OFDM at 65Mbps with 20MHz channel spacing
   */
  static WifiMode GetOfdmRate65MbpsBW20MHzShGi ();
  /**
   * Return a WifiMode for OFDM at 72.2Mbps with 20MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 72.2Mbps with 20MHz channel spacing
   */
  static WifiMode GetOfdmRate72_2MbpsBW20MHz ();
  /**
   * Return a WifiMode for OFDM at 15Mbps with 40MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 15Mbps with 40MHz channel spacing
   */
  static WifiMode GetOfdmRate15MbpsBW40MHz ();
  /**
   * Return a WifiMode for OFDM at 30Mbps with 40MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 30Mbps with 40MHz channel spacing
   */
  static WifiMode GetOfdmRate30MbpsBW40MHz ();
  /**
   * Return a WifiMode for OFDM at 45Mbps with 40MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 45Mbps with 40MHz channel spacing
   */
  static WifiMode GetOfdmRate45MbpsBW40MHz ();
  /**
   * Return a WifiMode for OFDM at 60Mbps with 40MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 60Mbps with 40MHz channel spacing
   */
  static WifiMode GetOfdmRate60MbpsBW40MHz ();
  /**
   * Return a WifiMode for OFDM at 90Mbps with 40MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 90Mbps with 40MHz channel spacing
   */
  static WifiMode GetOfdmRate90MbpsBW40MHz ();
  /**
   * Return a WifiMode for OFDM at 120Mbps with 40MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 120Mbps with 40MHz channel spacing
   */
  static WifiMode GetOfdmRate120MbpsBW40MHz ();
  /**
   * Return a WifiMode for OFDM at 135Mbps with 40MHz channel spacing.
   * The rate supports short guard interval.
   *
   * \return a WifiMode for OFDM at 135Mbps with 40MHz channel spacing
   */
  static WifiMode GetOfdmRate135MbpsBW40MHzShGi ();
  /**
   * Return a WifiMode for OFDM at 150Mbps with 40MHz channel spacing.
   *
   * \return a WifiMode for OFDM at 150Mbps with 40MHz channel spacing
   */
  static WifiMode GetOfdmRate150MbpsBW40MHz ();
/**
 * Return a WifiMode for OFDM at 300Kbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 300Kbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate300KbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 333.3Kbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 333.3Kbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate333_3KbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 600Kbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 600Kbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate600KbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 666_7Kbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 666_7Kbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate666_7KbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 900Kbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 900Kbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate900KbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 1Mbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 1Mbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate1MbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 1.2Mbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 1.2Mbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate1_2MbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 1.3333Mbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 1.3333Mbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate1_333_3MbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 1.8Mbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 1.8Mbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate1_8MbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 2Mbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 2Mbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate2MbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 2.4Mbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 2.4Mbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate2_4MbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 2.6667Mbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 2.6667Mbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate2_666_7MbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 2.7Mbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 2.7Mbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate2_7MbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 3Mbps with 1MHz channel spacing.
 * The rate supports short guard interval.
 *
 * \return a WifiMode for OFDM at 3Mbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate3MbpsBW1MHzShGi ();
/**
 * Return a WifiMode for OFDM at 3Mbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 3Mbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate3MbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 3.3333Mbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 3.3333Mbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate3_333_3MbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 3.6Mbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 3.6Mbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate3_6MbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 4Mbps with 1MHz channel spacing.
 * The rate supports short guard interval.
 *
 * \return a WifiMode for OFDM at 4Mbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate4MbpsBW1MHzShGi ();
/**
 * Return a WifiMode for OFDM at 4Mbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 4Mbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate4MbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 4.4444Mbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 4.4444Mbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate4_444_4MbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 150Kbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 150Kbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate150KbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 166.7Kbps with 1MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 166.7Kbps with 1MHz channel spacing
 */
static WifiMode GetOfdmRate166_7KbpsBW1MHz ();
/**
 * Return a WifiMode for OFDM at 650Kbps with 2MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 650Kbps with 2MHz channel spacing
 */
static WifiMode GetOfdmRate650KbpsBW2MHz ();
/**
 * Return a WifiMode for OFDM at 722.2Kbps with 2MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 722.2Kbps with 2MHz channel spacing
 */
static WifiMode GetOfdmRate722_2KbpsBW2MHz ();
/**
 * Return a WifiMode for OFDM at 1.3Mbps with 2MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 1.3Mbps with 2MHz channel spacing
 */
static WifiMode GetOfdmRate1_3MbpsBW2MHz ();
/**
 * Return a WifiMode for OFDM at 1.4444Mbps with 2MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 1.4444Mbps with 2MHz channel spacing
 */
static WifiMode GetOfdmRate1_444_4MbpsBW2MHz ();
/**
 * Return a WifiMode for OFDM at 1.95Mbps with 2MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 1.95Mbps with 2MHz channel spacing
 */
static WifiMode GetOfdmRate1_95MbpsBW2MHz ();
/**
 * Return a WifiMode for OFDM at 2.1667Mbps with 2MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 2.1667Mbps with 2MHz channel spacing
 */
static WifiMode GetOfdmRate2_166_7MbpsBW2MHz ();
/**
 * Return a WifiMode for OFDM at 2.6Mbps with 2MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 2.6Mbps with 2MHz channel spacing
 */
static WifiMode GetOfdmRate2_6MbpsBW2MHz ();
/**
 * Return a WifiMode for OFDM at 2.8889Mbps with 2MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 2.8889Mbps with 2MHz channel spacing
 */
static WifiMode GetOfdmRate2_8889MbpsBW2MHz ();
/**
 * Return a WifiMode for OFDM at 3.9Mbps with 2MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 3.9Mbps with 2MHz channel spacing
 */
static WifiMode GetOfdmRate3_9MbpsBW2MHz ();
/**
 * Return a WifiMode for OFDM at 4.3333Mbps with 2MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 4.3333Mbps with 2MHz channel spacing
 */
static WifiMode GetOfdmRate4_333_3MbpsBW2MHz ();
/**
 * Return a WifiMode for OFDM at 5.2Mbps with 2MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 5.2Mbps with 2MHz channel spacing
 */
static WifiMode GetOfdmRate5_2MbpsBW2MHz ();
/**
 * Return a WifiMode for OFDM at 5.7778Mbps with 2MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 5.7778Mbps with 2MHz channel spacing
 */
static WifiMode GetOfdmRate5_777_8MbpsBW2MHz ();
/**
 * Return a WifiMode for OFDM at 5.85Mbps with 2MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 5.85Mbps with 2MHz channel spacing
 */
static WifiMode GetOfdmRate5_85MbpsBW2MHz ();
/**
 * Return a WifiMode for OFDM at 6.5Mbps with 2MHz channel spacing.
 * The rate supports short guard interval.
 *
 * \return a WifiMode for OFDM at 6.5Mbps with 2MHz channel spacing
 */
static WifiMode GetOfdmRate6_5MbpsBW2MHzShGi ();
/**
 * Return a WifiMode for OFDM at 6.5Mbps with 2MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 6.5Mbps with 2MHz channel spacing
 */
static WifiMode GetOfdmRate6_5MbpsBW2MHz ();
/**
 * Return a WifiMode for OFDM at 7.2222Mbps with 2MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 7.2222Mbps with 2MHz channel spacing
 */
static WifiMode GetOfdmRate7_222_2MbpsBW2MHz ();
/**
 * Return a WifiMode for OFDM at 7.8Mbps with 2MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 7.8Mbps with 2MHz channel spacing
 */
static WifiMode GetOfdmRate7_8MbpsBW2MHz ();
/**
 * Return a WifiMode for OFDM at 8.6667Mbps with 2MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 8.6667Mbps with 2MHz channel spacing
 */
static WifiMode GetOfdmRate8_666_7MbpsBW2MHz ();
/**
 * Return a WifiMode for OFDM at 1.35Mbps with 4MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 1.35Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate1_35MbpsBW4MHz ();
/**
 * Return a WifiMode for OFDM at 1.5Mbps with 4MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 1.5Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate1_5MbpsBW4MHz ();
/**
 * Return a WifiMode for OFDM at 2.7Mbps with 4MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 2.7Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate2_7MbpsBW4MHz ();
/**
 * Return a WifiMode for OFDM at 3Mbps with 4MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 3Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate3MbpsBW4MHz ();
/**
 * Return a WifiMode for OFDM at 4.05Mbps with 4MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 4.05Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate4_05MbpsBW4MHz ();
/**
 * Return a WifiMode for OFDM at 4.5Mbps with 4MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 4.5Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate4_5MbpsBW4MHz ();
/**
 * Return a WifiMode for OFDM at 5.4Mbps with 4MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 5.4Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate5_4MbpsBW4MHz ();
/**
 * Return a WifiMode for OFDM at 6Mbps with 4MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 6Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate6MbpsBW4MHz ();
/**
 * Return a WifiMode for OFDM at 8.1Mbps with 4MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 8.1Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate8_1MbpsBW4MHz ();
/**
 * Return a WifiMode for OFDM at 9Mbps with 4MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 9Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate9MbpsBW4MHz ();
/**
 * Return a WifiMode for OFDM at 10.8Mbps with 4MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 10.8Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate10_8MbpsBW4MHz ();
/**
 * Return a WifiMode for OFDM at 12Mbps with 4MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 12Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate12MbpsBW4MHz ();
/**
 * Return a WifiMode for OFDM at 12.15Mbps with 4MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 12.15Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate12_15MbpsBW4MHz ();
/**
 * Return a WifiMode for OFDM at 13.5Mbps with 4MHz channel spacing.
 * The rate supports short guard interval.
 *
 * \return a WifiMode for OFDM at 13.5Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate13_5MbpsBW4MHzShGi ();
/**
 * Return a WifiMode for OFDM at 13.5Mbps with 4MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 13.5Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate13_5MbpsBW4MHz ();
/**
 * Return a WifiMode for OFDM at 15Mbps with 4MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 15Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate15MbpsBW4MHz ();
/**
 * Return a WifiMode for OFDM at 16.2Mbps with 4MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 16.2Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate16_2MbpsBW4MHz ();
/**
 * Return a WifiMode for OFDM at 18Mbps with 4MHz channel spacing.
 * The rate supports short guard interval.
 *
 * \return a WifiMode for OFDM at 18Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate18MbpsBW4MHzShGi ();
/**
 * Return a WifiMode for OFDM at 18Mbps with 4MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 18Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate18MbpsBW4MHz ();
/**
 * Return a WifiMode for OFDM at 20Mbps with 4MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 20Mbps with 4MHz channel spacing
 */
static WifiMode GetOfdmRate20MbpsBW4MHz ();
/**
 * Return a WifiMode for OFDM at 2.925Mbps with 8MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 2.925Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate2_925MbpsBW8MHz ();
/**
 * Return a WifiMode for OFDM at 3.25Mbps with 8MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 3.25Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate3_25MbpsBW8MHz ();
/**
 * Return a WifiMode for OFDM at 5.85Mbps with 8MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 5.85Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate5_85MbpsBW8MHz ();
/**
 * Return a WifiMode for OFDM at 6.5Mbps with 8MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 6.5Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate6_5MbpsBW8MHz ();
/**
 * Return a WifiMode for OFDM at 8.775Mbps with 8MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 8.775Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate8_775MbpsBW8MHz ();
/**
 * Return a WifiMode for OFDM at 9.75Mbps with 8MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 9.75Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate9_75MbpsBW8MHz ();
/**
 * Return a WifiMode for OFDM at 11.7Mbps with 8MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 11.7Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate11_7MbpsBW8MHz ();
/**
 * Return a WifiMode for OFDM at 13Mbps with 8MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 13Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate13MbpsBW8MHz ();
/**
 * Return a WifiMode for OFDM at 17.55Mbps with 8MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 17.55Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate17_55MbpsBW8MHz ();
/**
 * Return a WifiMode for OFDM at 19.5Mbps with 8MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 19.5Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate19_5MbpsBW8MHz ();
/**
 * Return a WifiMode for OFDM at 23.4Mbps with 8MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 23.4Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate23_4MbpsBW8MHz ();
/**
 * Return a WifiMode for OFDM at 26Mbps with 8MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 26Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate26MbpsBW8MHz ();
/**
 * Return a WifiMode for OFDM at 26.325Mbps with 8MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 26.325Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate26_325MbpsBW8MHz ();
/**
 * Return a WifiMode for OFDM at 29.25Mbps with 8MHz channel spacing.
 * This rate supporrts short guard interval.
 *
 * \return a WifiMode for OFDM at 29.25Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate29_25MbpsBW8MHzShGi ();
/**
 * Return a WifiMode for OFDM at 29.25Mbps with 8MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 29.25Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate29_25MbpsBW8MHz ();
/**
 * Return a WifiMode for OFDM at 32.5Mbps with 8MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 32.5Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate32_5MbpsBW8MHz ();
/**
 * Return a WifiMode for OFDM at 35.1Mbps with 8MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 35.1Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate35_1MbpsBW8MHz ();
/**
 * Return a WifiMode for OFDM at 39Mbps with 8MHz channel spacing.
 * This rate supports short guard interval.
 *
 * \return a WifiMode for OFDM at 39Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate39MbpsBW8MHzShGi ();
/**
 * Return a WifiMode for OFDM at 39Mbps with 8MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 39Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate39MbpsBW8MHz ();
/**
 * Return a WifiMode for OFDM at 43.3333Mbps with 8MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 43.3333Mbps with 8MHz channel spacing
 */
static WifiMode GetOfdmRate43_333_3MbpsBW8MHz ();
/**
 * Return a WifiMode for OFDM at 5.85Mbps with 16MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 5.85Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate5_85MbpsBW16MHz ();
/**
 * Return a WifiMode for OFDM at 6.5Mbps with 16MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 6.5Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate6_5MbpsBW16MHz ();
/**
 * Return a WifiMode for OFDM at 11.7Mbps with 16MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 11.7Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate11_7MbpsBW16MHz ();
/**
 * Return a WifiMode for OFDM at 13Mbps with 16MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 13Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate13MbpsBW16MHz ();
/**
 * Return a WifiMode for OFDM at 17.55Mbps with 16MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 17.55Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate17_55MbpsBW16MHz ();
/**
 * Return a WifiMode for OFDM at 19.5Mbps with 16MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 19.5Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate19_5MbpsBW16MHz ();
/**
 * Return a WifiMode for OFDM at 23.4Mbps with 16MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 23.4Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate23_4MbpsBW16MHz ();
/**
 * Return a WifiMode for OFDM at 26Mbps with 16MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 26Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate26MbpsBW16MHz ();
/**
 * Return a WifiMode for OFDM at 35.1Mbps with 16MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 35.1Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate35_1MbpsBW16MHz ();
/**
 * Return a WifiMode for OFDM at 39Mbps with 16MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 39Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate39MbpsBW16MHz ();
/**
 * Return a WifiMode for OFDM at 46.8Mbps with 16MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 46.8Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate46_8MbpsBW16MHz ();
/**
 * Return a WifiMode for OFDM at 52Mbps with 16MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 52Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate52MbpsBW16MHz ();
/**
 * Return a WifiMode for OFDM at 52.65Mbps with 16MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 52.65Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate52_65MbpsBW16MHz ();
/**
 * Return a WifiMode for OFDM at 58.5Mbps with 16MHz channel spacing.
 * This rate supports short guard interval.
 *
 * \return a WifiMode for OFDM at 58.5Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate58_5MbpsBW16MHzShGi ();
/**
 * Return a WifiMode for OFDM at 58.5Mbps with 16MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 58.5Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate58_5MbpsBW16MHz();
/**
 * Return a WifiMode for OFDM at 65Mbps with 16MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 65Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate65MbpsBW16MHz ();
/**
 * Return a WifiMode for OFDM at 70.2Mbps with 16MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 70.2Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate70_2MbpsBW16MHz ();
/**
 * Return a WifiMode for OFDM at 78Mbps with 16MHz channel spacing.
 * This rate supports short guards interval.
 *
 * \return a WifiMode for OFDM at 78Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate78MbpsBW16MHzShGi ();
/**
 * Return a WifiMode for OFDM at 78Mbps with 16MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 78Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate78MbpsBW16MHz ();
/**
 * Return a WifiMode for OFDM at 86.6667Mbps with 16MHz channel spacing.
 *
 * \return a WifiMode for OFDM at 86.6667Mbps with 16MHz channel spacing
 */
static WifiMode GetOfdmRate86_666_7MbpsBW16MHz ();
  /**
   * Public method used to fire a PhyTxBegin trace.
   * Implemented for encapsulation purposes.
   *
   * \param packet the packet being transmitted
   */
  void NotifyTxBegin (Ptr<const Packet> packet);
  /**
   * Public method used to fire a PhyTxEnd trace.
   * Implemented for encapsulation purposes.
   *
   * \param packet the packet that was transmitted
   */
  void NotifyTxEnd (Ptr<const Packet> packet);
  /**
   * Public method used to fire a PhyTxDrop trace.
   * Implemented for encapsulation purposes.
   *
   * \param packet the packet that was failed to transmitted
   */
  void NotifyTxDrop (Ptr<const Packet> packet, DropReason reason = DropReason::Unknown);
  /**
   * Public method used to fire a PhyRxBegin trace.
   * Implemented for encapsulation purposes.
   *
   * \param packet the packet being received
   */
  void NotifyRxBegin (Ptr<const Packet> packet);
  /**
   * Public method used to fire a PhyRxEnd trace.
   * Implemented for encapsulation purposes.
   *
   * \param packet the packet received
   */
  void NotifyRxEnd (Ptr<const Packet> packet);
  /**
   * Public method used to fire a PhyRxDrop trace.
   * Implemented for encapsulation purposes.
   *
   * \param packet the packet that was not successfully received
   */
  void NotifyRxDrop (Ptr<const Packet> packet, DropReason reason = DropReason::Unknown);

  /**
   * Public method used to fire a MonitorSniffer trace for a wifi packet being received.
   * Implemented for encapsulation purposes.
   *
   * \param packet the packet being received
   * \param channelFreqMhz the frequency in MHz at which the packet is
   *        received. Note that in real devices this is normally the
   *        frequency to which  the receiver is tuned, and this can be
   *        different than the frequency at which the packet was originally
   *        transmitted. This is because it is possible to have the receiver
   *        tuned on a given channel and still to be able to receive packets
   *        on a nearby channel.
   * \param channelNumber the channel on which the packet is received
   * \param rate the PHY data rate in units of 500kbps (i.e., the same
   *        units used both for the radiotap and for the prism header)
   * \param isShortPreamble true if short preamble is used, false otherwise
   * \param txVector the txvector that holds rx parameters
   * \param signalDbm signal power in dBm
   * \param noiseDbm  noise power in dBm
   */
  void NotifyMonitorSniffRx (Ptr<const Packet> packet, uint16_t channelFreqMhz,
                             uint16_t channelNumber, uint32_t rate,
                             bool isShortPreamble, WifiTxVector txvector,
                             double signalDbm, double noiseDbm);

  /**
   * TracedCallback signature for monitor mode receive events.
   *
   *
   * \param packet the packet being received
   * \param channelFreqMhz the frequency in MHz at which the packet is
   *        received. Note that in real devices this is normally the
   *        frequency to which  the receiver is tuned, and this can be
   *        different than the frequency at which the packet was originally
   *        transmitted. This is because it is possible to have the receiver
   *        tuned on a given channel and still to be able to receive packets
   *        on a nearby channel.
   * \param channelNumber the channel on which the packet is received
   * \param rate the PHY data rate in units of 500kbps (i.e., the same
   *        units used both for the radiotap and for the prism header)
   * \param isShortPreamble true if short preamble is used, false otherwise
   * \param txVector the txvector that holds rx parameters
   * \param signalDbm signal power in dBm
   * \param noiseDbm noise power in dBm
   */
  typedef void (* MonitorSnifferRxCallback)(Ptr<const Packet> packet, uint16_t channelFreqMhz,
                                            uint16_t channelNumber, uint32_t rate,
                                            bool isShortPreamble, WifiTxVector txvector,
                                            double signalDbm, double noiseDbm);

  /**
   * Public method used to fire a MonitorSniffer trace for a wifi packet being transmitted.
   * Implemented for encapsulation purposes.
   *
   * \param packet the packet being transmitted
   * \param channelFreqMhz the frequency in MHz at which the packet is
   *        transmitted.
   * \param channelNumber the channel on which the packet is transmitted
   * \param rate the PHY data rate in units of 500kbps (i.e., the same
   *        units used both for the radiotap and for the prism header)
   * \param isShortPreamble true if short preamble is used, false otherwise
   * \param txVector the txvector that holds tx parameters
   */
  void NotifyMonitorSniffTx (Ptr<const Packet> packet, uint16_t channelFreqMhz,
                             uint16_t channelNumber, uint32_t rate,
                             bool isShortPreamble, WifiTxVector txvector);

  /**
   * TracedCallback signature for monitor mode transmit events.
   *
   * \param packet the packet being transmitted
   * \param channelFreqMhz the frequency in MHz at which the packet is
   *        transmitted.
   * \param channelNumber the channel on which the packet is transmitted
   * \param rate the PHY data rate in units of 500kbps (i.e., the same
   *        units used both for the radiotap and for the prism header)
   * \param isShortPreamble true if short preamble is used, false otherwise
   * \param txVector the txvector that holds tx parameters
   */
  typedef void (* MonitorSnifferTxCallback)(const Ptr<const Packet> packet, uint16_t channelFreqMhz,
                                            uint16_t channelNumber, uint32_t rate,
                                            bool isShortPreamble, WifiTxVector txvector);

  /**
   * Assign a fixed random variable stream number to the random variables
   * used by this model. Return the number of streams (possibly zero) that
   * have been assigned.
   *
   * \param stream first stream index to use
   * \return the number of stream indices assigned by this model
   */
  virtual int64_t AssignStreams (int64_t stream) = 0;

  /**
   * \param freq the operating frequency on this node.
   */
  virtual void SetFrequency (uint32_t freq) = 0;
  /**
   * \return the operating frequency on this node
   */
  virtual uint32_t GetFrequency (void) const = 0;
  /**
   * \param tx the number of transmitters on this node.
   */
  virtual void SetNumberOfTransmitAntennas (uint32_t tx) = 0;
  /**
   * \return the number of transmit antenna on this device
   */
  virtual uint32_t GetNumberOfTransmitAntennas (void) const = 0;
  /**
  * \param rx the number of receivers on this node.
  */
  virtual void SetNumberOfReceiveAntennas (uint32_t rx) = 0;
  /**
   * \return the number of receivers on this node.
   */
  virtual uint32_t GetNumberOfReceiveAntennas (void) const = 0;
  /**
   * \param guardInterval Enable or disable short guard interval
   */
  virtual void SetGuardInterval (bool guardInterval) = 0;
  /**
   * \return true if short guard interval is supported, false otherwise
   */
  virtual bool GetGuardInterval (void) const = 0;
  /**
   * \param ldpc Enable or disable LDPC
   */
  virtual void SetLdpc (bool ldpc) = 0;
  /**
   * \return true if LDPC is supported, false otherwise
   */
  virtual bool GetLdpc (void) const = 0;
  /**
   * \param stbc Enable or disable STBC is supported
   */
  virtual void SetStbc (bool stbc) = 0;
  /**
   * \return true if STBC is supported, false otherwise
   */
  virtual bool GetStbc (void) const = 0;
  /**
   * \param greenfield Enable or disable GreenField
   */
  virtual void SetGreenfield (bool greenfield) = 0;
  /**
   * \return true if Greenfield is supported, false otherwise
   */
  virtual bool GetGreenfield (void) const = 0;
  /**
   * \param S1g1Mfield Enable or disable GreenField
   */
  virtual void SetS1g1Mfield (bool s1g1mfield) = 0;
  /**
   * \return true if S1g1Mfield is supported, false otherwise
   */
  virtual bool GetS1g1Mfield (void) const = 0;
  /**
   * \param S1gShortfield Enable or disable GreenField
   */
  virtual void SetS1gShortfield (bool s1gshortfield) = 0;
  /**
   * \return true if S1gShortfield is supported, false otherwise
   */
  virtual bool GetS1gShortfield (void) const = 0;
  /**
   * \param S1gLongfield Enable or disable GreenField
   */
  virtual void SetS1gLongfield (bool s1glongfield) = 0;
  /**
   * \return true if S1gLongfield is supported, false otherwise
   */
  virtual bool GetS1gLongfield (void) const = 0;
  /**
   * \return the channel width
   */
  virtual uint32_t GetChannelWidth (void) const = 0;
  /**
   *  \param channelwidth channel width
   */
  virtual void SetChannelWidth (uint32_t channelwidth) = 0;
  WifiModeList m_deviceRateSet;

private:
  /**
   * The trace source fired when a packet begins the transmission process on
   * the medium.
   *
   * \see class CallBackTraceSource
   */
  TracedCallback<Ptr<const Packet> > m_phyTxBeginTrace;

  /**
   * The trace source fired when a packet ends the transmission process on
   * the medium.
   *
   * \see class CallBackTraceSource
   */
  TracedCallback<Ptr<const Packet> > m_phyTxEndTrace;

  /**
   * The trace source fired when the phy layer drops a packet as it tries
   * to transmit it.
   *
   * \see class CallBackTraceSource
   */
  TracedCallback<Ptr<const Packet> > m_phyTxDropTrace;

  TracedCallback<Ptr<const Packet>, DropReason> m_phyTxDropWithDropReasonTrace;

  /**
   * The trace source fired when a packet begins the reception process from
   * the medium.
   *
   * \see class CallBackTraceSource
   */
  TracedCallback<Ptr<const Packet> > m_phyRxBeginTrace;

  /**
   * The trace source fired when a packet ends the reception process from
   * the medium.
   *
   * \see class CallBackTraceSource
   */
  TracedCallback<Ptr<const Packet> > m_phyRxEndTrace;

  /**
   * The trace source fired when the phy layer drops a packet it has received.
   *
   * \see class CallBackTraceSource
   */
  TracedCallback<Ptr<const Packet> > m_phyRxDropTrace;

  TracedCallback<Ptr<const Packet>, DropReason> m_phyRxDropWithDropReasonTrace;

  /**
   * A trace source that emulates a wifi device in monitor mode
   * sniffing a packet being received.
   *
   * As a reference with the real world, firing this trace
   * corresponds in the madwifi driver to calling the function
   * ieee80211_input_monitor()
   *
   * \see class CallBackTraceSource
   */
  TracedCallback<Ptr<const Packet>, uint16_t, uint16_t, uint32_t, bool, WifiTxVector, double, double> m_phyMonitorSniffRxTrace;

  /**
   * A trace source that emulates a wifi device in monitor mode
   * sniffing a packet being transmitted.
   *
   * As a reference with the real world, firing this trace
   * corresponds in the madwifi driver to calling the function
   * ieee80211_input_monitor()
   *
   * \see class CallBackTraceSource
   */
  TracedCallback<Ptr<const Packet>, uint16_t, uint16_t, uint32_t, bool, WifiTxVector> m_phyMonitorSniffTxTrace;

  uint32_t m_totalAmpduNumSymbols; //!< Number of symbols previously transmitted for the MPDUs in an A-MPDU, used for the computation of the number of symbols needed for the last MPDU in the A-MPDU
  uint32_t m_totalAmpduSize;       //!< Total size of the previously transmitted MPDUs in an A-MPDU, used for the computation of the number of symbols needed for the last MPDU in the A-MPDU
};

/**
 * \param os          output stream
 * \param state       wifi state to stringify
 * \return output stream
 */
std::ostream& operator<< (std::ostream& os, enum WifiPhy::State state);

} //namespace ns3

#endif /* WIFI_PHY_H */
