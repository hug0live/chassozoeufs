import 'lan_party_service_base.dart';
import 'lan_party_service_stub.dart'
    if (dart.library.io) 'lan_party_service_io.dart'
    as impl;

export 'lan_party_service_base.dart';

LanPartyService createLanPartyService() => impl.createLanPartyService();
