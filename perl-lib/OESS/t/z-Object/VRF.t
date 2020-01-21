#!/usr/bin/perl

use strict;
use warnings;

use FindBin;
my $path;

BEGIN {
    if ($FindBin::Bin =~ /(.*)/) {
        $path = $1;
    }
}
use lib "$path/..";


use Data::Dumper;
use Test::More tests => 8;

use OESSDatabaseTester;

use OESS::DB;
use OESS::VRF;

OESSDatabaseTester::resetOESSDB(
    config => "$path/../conf/database.xml",
    dbdump => "$path/../conf/oess_known_state.sql"
);

my $db = new OESS::DB(
   config => "$path/../conf/database.xml"
);

my $workgroup_id = 31;

my $vrf = new OESS::VRF(
    db    => $db,
    model => {
        name           => 'Test_4',
        description    => 'Test_4',
        local_asn      =>  1,
        workgroup_id   =>  $workgroup_id,
        provision_time => -1,
        remove_time    => -1,
        created_by     => 11,
        last_modified_by => 11
    }
);
my $ok = $vrf->create;
ok($ok, "Created vrf $vrf->{vrf_id}.");

my $endpoints = [
    {
        bandwidth => 0,
        mtu => 1500,
        tag => 2007,
        peerings => [
            { peer_asn => 7, md5_key => '', local_ip => '192.168.7.2/31', peer_ip => '192.168.7.3/31', version => 4 }
        ],
        entity => 'B University-Metropolis'
    },
    {
        bandwidth => 0,
        mtu => 1500,
        tag => 2008,
        peerings => [
            { peer_asn => 8, md5_key => '', local_ip => '192.168.8.2/31', peer_ip => '192.168.8.3/31', version => 4 }
        ],
        entity => 'Big State TeraPOP'
    }
];

foreach my $ep (@$endpoints) {
    my $entity = new OESS::Entity(db => $db, name => $ep->{entity});
    my $interface = $entity->select_interface(
        inner_tag    => $ep->{inner_tag},
        tag          => $ep->{tag},
        workgroup_id => $workgroup_id
    );
    $ep->{type}         = 'vrf';
    $ep->{entity_id}    = $entity->{entity_id};
    $ep->{interface}    = $interface->{name};
    $ep->{interface_id} = $interface->{interface_id};
    $ep->{node}         = $interface->{node}->{name};
    $ep->{node_id}      = $interface->{node}->{node_id};
    $ep->{cloud_interconnect_id}   = $interface->cloud_interconnect_id;
    $ep->{cloud_interconnect_type} = $interface->cloud_interconnect_type;

    my $endpoint = new OESS::Endpoint(db => $db, model => $ep);
    my ($ep_id, $ep_err) = $endpoint->create(
        vrf_id       => $vrf->vrf_id,
        workgroup_id => $workgroup_id
    );
    ok(!defined $ep_err, "Created endpoint $endpoint->{vrf_endpoint_id}.");
    if (defined $ep_err) {
        warn "$ep_err";
    }
    $vrf->add_endpoint($endpoint);

    foreach my $peering (@{$ep->{peerings}}) {
        my $peer = new OESS::Peer(db => $db, model => $peering);
        my ($peer_id, $peer_err) = $peer->create(vrf_ep_id => $endpoint->vrf_endpoint_id);
        ok(!defined $peer_err, "Created peer $peer->{vrf_ep_peer_id}.");
        if (defined $peer_err) {
            warn "$peer_err";
        }
        $endpoint->add_peer($peer);
    }
}

my $loaded_vrf = new OESS::VRF(db => $db, vrf_id => $vrf->vrf_id);
$loaded_vrf->load_endpoints;
foreach my $ep (@{$loaded_vrf->endpoints}) {
    # Calling update_db without first calling load_peers would remove
    # all peers from the vrf. Verify that peers are only removed if
    # called via OESS::Endpoint->remove_peer.
    #
    # $ep->load_peers;
}
$loaded_vrf->update_db;

my $loaded_vrf2 = new OESS::VRF(db => $db, vrf_id => $vrf->vrf_id);
$loaded_vrf2->load_endpoints;
foreach my $ep (@{$loaded_vrf2->endpoints}) {
    $ep->load_peers;
    ok(@{$ep->peers} == 1, "Looked up exactly 1 Peer on Endpoint.");
}
# warn Dumper($loaded_vrf2->to_hash);

$ok = $vrf->decom(user_id => 1);
ok($ok, "VRF Decom'd");
