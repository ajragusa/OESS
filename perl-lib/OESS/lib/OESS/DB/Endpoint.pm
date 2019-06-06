#!/usr/bin/perl

use strict;
use warnings;

package OESS::DB::Endpoint;

use Data::Dumper;


=head1 OESS::DB::Endpoint

    use OESS::DB::Endpoint;

=cut

=head2 fetch_all

    my ($endpoints, $error) = OESS::DB::Endpoint::fetch_all(
        db           => new OESS::DB,
        circuit_id   => 100,          # Optional
        vrf_id       => 100,          # Optional
        entity_id    => 100,          # Optional
        node_id      => 100,          # Optional
        interface_id => 100           # Optional
    );
    warn $error if defined $error;

fetch_all returns a list of all active endpoints for of both Circuits
and VRFs. Each VRF Endpoint will contain C<vrf_ep_id> and Circuit
Endpoints will contain C<circuit_ep_id>.

    {
        vrf_ep_id           => 3,                   # Optional
        circuit_ep_id       => 3,                   # Optional
        entity              => 'mx960-1',
        entity_id           => 3,
        node                => 'test.grnoc.iu.edu',
        node_id             => 2,
        interface           => 'xe-7/0/2',
        description         => 'na',
        interface_id        => 57,
        unit                => 6,
        tag                 => 6,
        inner_tag           => undef,
        bandwidth           => 0,
        cloud_account_id    => undef,
        cloud_connection_id => undef,
        mtu                 => 9000,
        operational_state   => 'up'
    }

=cut
sub fetch_all {
    my $args = {
        db => undef,
        circuit_id => undef,
        vrf_id => undef,
        entity_id => undef,
        interface_id => undef,
        node_id => undef,
        @_
    };

    return (undef, 'Required argument `db` is missing.') if !defined $args->{db};

    my $type = undef;

    my $params = [];
    my $values = [];

    # When circuit_id or vrf_id is defined we change our endpoint_type
    # which is used to select between our circuit_ep and vrf_ep
    # endpoint queries.
    if (defined $args->{circuit_id}) {
        $type = 'circuit';
        push @$params, 'circuit_ep.circuit_id=?';
        push @$values, $args->{circuit_id};
    }
    if (defined $args->{vrf_id}) {
        $type = 'vrf';
        push @$params, 'vrf_ep.vrf_id=?';
        push @$values, $args->{vrf_id};
    }
    if (defined $args->{entity_id}) {
        push @$params, 'entity.entity_id=?';
        push @$values, $args->{entity_id};
    }
    if (defined $args->{interface_id}) {
        push @$params, 'interface.interface_id=?';
        push @$values, $args->{interface_id};
    }
    if (defined $args->{node_id}) {
        push @$params, 'node.node_id=?';
        push @$values, $args->{node_id};
    }

    my $where = (@$params > 0) ? 'WHERE ' . join(' AND ', @$params) : 'WHERE 1 ';

    my $q;
    my $endpoints = [];

    if (!defined $type || $type eq 'circuit') {
        #       circuit_ep_id: 36
        #          circuit_id: 30
        #           entity_id: 3
        #              entity: mx960-1
        #        interface_id: 57
        #           interface: xe-7/0/2
        #         description: 'na'
        #   operational_state: up
        #             node_id: 2
        #                node: mx960-1.sdn-test.grnoc.iu.edu
        #                unit: 327
        #                 tag: 327
        #           inner_tag: NULL
        #           bandwidth: NULL
        #                 mtu: 9000
        #    cloud_account_id: NULL
        # cloud_connection_id: NULL

        $q = "
            SELECT circuit_ep.circuit_edge_id AS circuit_ep_id, circuit_ep.circuit_id,
                   entity.entity_id, entity.name AS entity,
                   interface.interface_id, interface.name AS interface, interface.operational_state, interface.description,
                   node.node_id, node.name AS node,
                   unit, extern_vlan_id AS tag, inner_tag,
                   bandwidth, mtu, cloud_account_id, cloud_connection_id
            FROM circuit_edge_interface_membership AS circuit_ep
            JOIN interface ON interface.interface_id=circuit_ep.interface_id
            JOIN node ON node.node_id=interface.node_id
            JOIN interface_acl ON interface_acl.interface_id=interface.interface_id
            LEFT JOIN entity ON entity.entity_id=interface_acl.entity_id
            LEFT JOIN cloud_connection_vrf_ep as cloud on cloud.circuit_ep_id=circuit_ep.circuit_edge_id
            $where
            AND circuit_ep.end_epoch = -1
            AND (circuit_ep.extern_vlan_id >= interface_acl.vlan_start)
            AND (circuit_ep.extern_vlan_id <= interface_acl.vlan_end)
        ";
        my $circuit_endpoints = $args->{db}->execute_query($q, $values);
        if (!defined $circuit_endpoints) {
            return (undef, "Couldn't find Circuit Endpoints: " . $args->{db}->get_error);
        }

        foreach my $e (@$circuit_endpoints) {
            push @$endpoints, $e;
        }
    }

    if (!defined $type || $type eq 'vrf') {
        #           vrf_ep_id: 3
        #              vrf_id: 30
        #           entity_id: 3
        #              entity: mx960-1
        #        interface_id: 57
        #           interface: xe-7/0/2
        #         description: 'na'
        #   operational_state: up
        #             node_id: 2
        #                node: mx960-1.sdn-test.grnoc.iu.edu
        #                unit: 6
        #                 tag: 6
        #           inner_tag: NULL
        #           bandwidth: 0
        #                 mtu: 9000
        #    cloud_account_id: NULL
        # cloud_connection_id: NULL

        $q = "
            SELECT vrf_ep.vrf_ep_id, vrf_ep.vrf_id,
                   entity.entity_id, entity.name AS entity,
                   interface.interface_id, interface.name AS interface, interface.operational_state, interface.description,
                   node.node_id, node.name AS node,
                   unit, tag, inner_tag,
                   bandwidth, mtu, cloud_account_id, cloud_connection_id
            FROM vrf_ep
            JOIN interface ON interface.interface_id=vrf_ep.interface_id
            JOIN node ON node.node_id=interface.node_id
            JOIN interface_acl ON interface_acl.interface_id=interface.interface_id
            LEFT JOIN entity ON entity.entity_id=interface_acl.entity_id
            LEFT JOIN cloud_connection_vrf_ep as cloud on cloud.vrf_ep_id=vrf_ep.vrf_ep_id
            $where
            AND (vrf_ep.tag >= interface_acl.vlan_start)
            AND (vrf_ep.tag <= interface_acl.vlan_end)
        ";
        my $vrf_endpoints = $args->{db}->execute_query($q, $values);
        if (!defined $vrf_endpoints) {
            return (undef, "Couldn't find VRF Endpoints: " . $args->{db}->get_error);
        }

        foreach my $e (@$vrf_endpoints) {
            push @$endpoints, $e;
        }
    }

    return ($endpoints, undef);
}

=head2 update_vrf

=cut
sub update_vrf {
    my %params = @_;
    my $db = $params{db};
    my $endpoint = $params{endpoint};

    my $reqs = [];
    my $args = [];
    my $set = '';
    

    if(!defined($endpoint->{vrf_endpoint_id})) {
        return;
    }
    
    if(defined($endpoint->{inner_tag})){
        push @$reqs, 'inner_tag=?';
        push @$args, $endpoint->{inner_tag};
    }
    
    if(defined($endpoint->{tag})){
        push @$reqs, 'tag=?';
        push @$args, $endpoint->{tag};
    }
    
    if(defined($endpoint->{bandwidth})){
        push @$reqs, 'bandwidth=?';
        push @$args, $endpoint->{bandwidth};
    }

    if(defined($endpoint->{interface}) &&
       defined($endpoint->{interface}->{interface_id})) {
        push @$reqs, 'interface_id=?';
        push @$args, $endpoint->{interface}->{interface_id};
    }

    if(defined($endpoint->{state})) {
        push @$reqs, 'state=?';
        push @$args, $endpoint->{state};
    }
    
    if(defined($endpoint->{unit})){
        push @$reqs, 'unit=?';
        push @$args, $endpoint->{unit};
    }

    $set .= join(', ', @$reqs);
    push @$args, $endpoint->{vrf_endpoint_id};
    my $result = $db->execute_query(
        "UPDATE vrf_ep SET $set WHERE vrf_ep_id=?",
        $args
    );
    return $result;
}

=head2 remove_circuit_edge_membership

=cut
sub remove_circuit_edge_membership{
    my %params = @_;
    my $db = $params{db};
    my $endpoint = $params{endpoint};

    my $result = $db->execute_query(
        "DELETE FROM circuit_edge_interface_membership ".
        "WHERE circuit_edge_id = ? AND end_epoch = -1",
        [$endpoint->{circuit_ep_id}]);
    return $result;
}

=head2 add_circuit_edge_membership

=cut
sub add_circuit_edge_membership{
    my %params = @_;
    my $db = $params{db};
    my $endpoint = $params{endpoint};

    my $result = $db->execute_query(
        "INSERT INTO circuit_edge_interface_membership (".
            "interface_id, ".
            "circuit_id, ".
            "end_epoch, ".
            "start_epoch, ".
            "extern_vlan_id, ".
            "inner_tag, ".
            "unit".
            ") VALUES (?, ?, ?, UNIX_TIMESTAMP(NOW()), ?, ?, ?)",
            [$endpoint->{interface_id},
             $endpoint->{circuit_id},
             -1,
             $endpoint->{tag},
             $endpoint->{inner_tag},
             $endpoint->{unit}]);
    return $result;
}

=head2 update_circuit_edge_membership

=cut
sub update_circuit_edge_membership{
    my %params = @_;
    my $db = $params{db};
    my $endpoint = $params{endpoint};

    my $result = $db->execute_query(
        "INSERT INTO circuit_edge_interface_membership (".
            "interface_id, ".
            "circuit_id, ".
            "end_epoch, ".
            "start_epoch,".
            "extern_vlan_id, ".
            "inner_tag, ".
            "circuit_edge_id, ".
            "unit".
            ") VALUES (?, ?, ?, UNIX_TIMESTAMP(NOW()), ?, ?, ?, ?)",
            [$endpoint->{interface_id},
             $endpoint->{circuit_id},
             -1,
             $endpoint->{tag},
             $endpoint->{inner_tag},
             $endpoint->{circuit_ep_id},
             $endpoint->{unit}]);
    return $result;
}

=head2 remove_vrf_ep

    my $error = OESS::DB::Endpoint::remove_vrf_ep(
        db => $db,
        vrf_ep_id => 100
    );

=cut
sub remove_vrf_ep {
    my $args = {
        db        => undef,
        vrf_ep_id => undef,
        @_
    };

    my $ok = $args->{db}->execute_query(
        "delete from vrf_ep where vrf_ep_id=?",
        [$args->{vrf_ep_id}]
    );
    if (!$ok) {
        return $args->{db}->get_error;
    }

    return;
}

=head2 remove_vrf_peers

=cut
sub remove_vrf_peers{
    my %params = @_;
    my $db = $params{db};
    my $endpoint = $params{endpoint};

    my $result = $db->execute_query(
        "DELETE FROM vrf_ep_peer WHERE vrf_ep_peer_id=?",
        [$endpoint->{vrf_endpoint_id}]);
    return $result;
}

=head2 add_vrf_peers

=cut
sub add_vrf_peers{
    my %params = @_;
    my $db = $params{db};
    my $endpoint = $params{endpoint};

    my $values = [];
    my $params = [];

    if(scalar(@{$endpoint->{peers}}) == 0){
        return 1;
    }

    foreach my $peer (@{$endpoint->{peers}}){
        push @$params, '(?, ?, ?, ?, ?, ?, ?, ?)';
        
        push @$values, $peer->{vrf_ep_peer_id};
        push @$values, $peer->{peer_ip};
        push @$values, $peer->{peer_asn};
        push @$values, $peer->{vrf_ep_id};
        push @$values, $peer->{operational_state};
        push @$values, $peer->{state};
        push @$values, $peer->{local_ip};
        push @$values, $peer->{md5_key};
    }
    
    my $param_str = join(', ', @$params);
    my $result = $db->execute_query(
        "INSERT INTO vrf_ep_peer (".
            "vrf_ep_peer_id, ".
            "peer_ip, ".
            "peer_asn, ".
            "vrf_ep_id,".
            "operational_state, ".
            "state, ".
            "local_ip, ".
            "md5_key".
            ") VALUES $param_str", $values);
    return $result;
}

=head2 find_available_unit

=cut
sub find_available_unit{
    my $args = {
        db           => undef,
        interface_id => undef,
        tag          => undef,
        inner_tag    => undef,
        @_
    };

    if (!defined $args->{db} || !defined $args->{interface_id}) {
        return;
    }

    # To preserve backwards compatibility with existing VLANs we find
    # an available unit >= 5000.
    my $used_vrf_units = $args->{db}->execute_query(
        "select unit from vrf_ep where unit >= 5000 and state = 'active' and interface_id = ?",
        [$args->{interface_id}]
    );

    my $circuit_units_q = "
        select unit
        from circuit_edge_interface_membership
        where interface_id = ? and end_epoch = -1 and circuit_id in (
            select circuit.circuit_id
            from circuit
            join circuit_instantiation on circuit.circuit_id=circuit_instantiation.circuit_id
                 and circuit.circuit_state = 'active'
                 and circuit_instantiation.circuit_state = 'active'
                 and circuit_instantiation.end_epoch = -1
        )";
    my $used_circuit_units = $args->{db}->execute_query($circuit_units_q, [$args->{interface_id}]);

    my %used;

    foreach my $used_vrf_unit (@$used_vrf_units){
        $used{$used_vrf_unit->{'unit'}} = 1;
    }

    foreach my $used_circuit_units (@{$used_circuit_units}){
        $used{$used_circuit_units->{'unit'}} = 1;
    }

    for (my $i = 5000; $i < 16000; $i++) {
        if (defined $used{$i} && $used{$i} == 1) {
            next;
        }
        return $i;
    }

    return;
}

1;
