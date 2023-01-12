# BlueEDM


Download engine monitoring data from your [JPI EDM](https://www.jpinstruments.com) engine monitor directly to your iPhone or iPad. Make the dowloaded data available to your favorite tools like [Savvy](https://www.savvyaviation.com) directly from your cockpit. No need to carry a laptop with you to access your airplane's engine data. Verify and review flight data directly after landing. Besides downloading engine monitoring files via Bluetooth and the EDM serial interface, BlueEDM receives files via the regular iOS sharing channels (e.g. Airdrop). Just get an EDM file, make sure it has a .jpi ending and share it with your iOS device.
Also BlueEDM lets you share individual flight data or complete EDM files as JSON data. You may use standard tools to convert to .csv format then.

BlueEDM is built on top of [EdmParser](https://github.com/staski/EdmParser), a Swift based EDM enginge monitoring file format parser. This in turn is inspired to a large extent by [EdmTools](https://github.com/wannamak/edmtools)and [JPIHack.cpp](https://www.geocities.ws/jpihack/jpihackcpp.txt)

As a prerequisite for downloading data from an EDM device using Bluetooth, you need a serial cable, compatible with the EDM pin assignments and a serial Bluetooth adapter. We recommend the LinTech Bluetooth Low Energy RS232 Adapter.

There is no standardized Bluetooth RS232 interface. However, the LinTech Bluetooth adapter implements a proprietary serial protocol over Bluetooth Low Energy (BLE). This app uses LinTech’s BLE RS232 service to connect to EDMs serial interface.

See https://fly.venus-flytrap.de/BlueEDM for more details

