require 'spec_helper'

describe 'Private' do
  include_context :terraform

  let :created_vpc do
    vpc("vpc-#{variables.component}-#{variables.deployment_identifier}")
  end
  let :private_subnets do
    variables.availability_zones.split(',').map do |zone|
      subnet("private-subnet-#{variables.component}-#{variables.deployment_identifier}-#{zone}")
    end
  end
  let :private_route_table do
    route_table("private-routetable-#{variables.component}-#{variables.deployment_identifier}")
  end
  let :nat_gateway do
    response = ec2_client.describe_nat_gateways({
        filter: [{ name: 'vpc-id', values: [created_vpc.id] }]
    })
    response.nat_gateways.single_resource(created_vpc.id)
  end

  context 'subnets' do
    it 'has a Component tag on each subnet' do
      private_subnets.each do |subnet|
        expect(subnet).to(have_tag('Component').value(variables.component))
      end
    end

    it 'has a DeploymentIdentifier tag on each subnet' do
      private_subnets.each do |subnet|
        expect(subnet).to(have_tag('DeploymentIdentifier')
            .value(variables.deployment_identifier))
      end
    end

    it 'has a Tier of private on each subnet' do
      private_subnets.each do |subnet|
        expect(subnet).to(have_tag('Tier').value('private'))
      end
    end

    it 'associates each subnet with the created VPC' do
      private_subnets.each do |subnet|
        expect(subnet.vpc_id)
            .to(eq(created_vpc.id))
      end
    end

    it 'distributes subnets across availability zones' do
      variables.availability_zones.split(',').map do |zone|
        expect(private_subnets.map(&:availability_zone)).to(include(zone))
      end
    end

    it 'uses unique /24 networks relative to the VPC CIDR for each subnet' do
      vpc_cidr = NetAddr::CIDR.create(variables.vpc_cidr)

      private_subnets.each do |subnet|
        subnet_cidr = NetAddr::CIDR.create(subnet.cidr_block)

        expect(subnet_cidr.netmask).to(eq('/24'))
        expect(vpc_cidr.contains?(subnet_cidr)).to(be(true))
      end

      expect(private_subnets.map(&:cidr_block).uniq.length).to(eq(private_subnets.length))
    end

    it 'exposes the private subnet IDs as an output' do
      expected_private_subnet_ids = private_subnets.map(&:id).join(',')
      actual_private_subnet_ids = Terraform.output(
          name: 'private_subnet_ids')

      expect(actual_private_subnet_ids).to(eq(expected_private_subnet_ids))
    end

    it 'exposes the private subnet CIDR blocks as an output' do
      expected_private_subnet_ids = private_subnets.map(&:cidr_block).join(',')
      actual_private_subnet_ids = Terraform.output(
          name: 'private_subnet_cidr_blocks')

      expect(actual_private_subnet_ids).to(eq(expected_private_subnet_ids))
    end
  end

  context 'route table' do
    it 'has a Component tag' do
      expect(private_route_table).to(have_tag('Component').value(variables.component))
    end

    it 'has a DeploymentIdentifier' do
      expect(private_route_table).to(have_tag('DeploymentIdentifier')
          .value(variables.deployment_identifier))
    end

    it 'has a Tier of private' do
      expect(private_route_table).to(have_tag('Tier').value('private'))
    end

    it 'is associated to the created VPC' do
      expect(private_route_table.vpc_id).to(eq(created_vpc.id))
    end

    it 'has a route to the NAT gateway for all internet traffic' do
      expect(private_route_table)
          .to(have_route('0.0.0.0/0').target(gateway: nat_gateway.nat_gateway_id))
    end

    it 'is associated to each subnet' do
      private_subnets.each do |subnet|
        expect(private_route_table).to(have_subnet(subnet.id))
      end
    end
  end
end
