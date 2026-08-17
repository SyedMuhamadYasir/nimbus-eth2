# beacon_chain
# Copyright (c) 2026 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at https://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at https://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

{.push raises: [], gcsafe.}
{.used.}

import unittest2
import ../beacon_chain/sync/[sync_range, response_utils],
       ../beacon_chain/spec/[forks, column_map]


type
  GloasBlockChainItem =
    tuple[fork: ConsensusFork, slot, root, parentRoot, commitments: int]

  GloasBlockChainResultItem =
    tuple[fork: ConsensusFork, slot, root, parentRoot, commitments, env: int]

  GloasEnvelopeChainItem =
    tuple[slot, root, parentRoot: int]

func init(t: typedesc[SyncRange], srange: Slice[Slot]): SyncRange =
  SyncRange(slot: srange.a, count: uint64(len(srange)))

func createDigest(data: int): Eth2Digest =
  var res = Eth2Digest()
  let tmp = uint64(data).toBytesBE()
  copyMem(addr res.data[0], addr tmp[0], 8)
  res

func genKzgCommitment(index: int): KzgCommitment =
  var res: KzgCommitment
  let tmp = uint64(index).toBytesLE()
  copyMem(addr res.bytes[0], unsafeAddr tmp[0], sizeof(uint64))
  res

func genKzgCommitments(count: int): gloas.KzgCommitments =
  var res: seq[KzgCommitment]
  for i in 0 ..< count:
    res.add(genKzgCommitment(i))
  gloas.KzgCommitments(res)

func createGloasBlock(
    slot: Slot,
    root: Eth2Digest,
    parentRoot: Eth2Digest,
    commitmentsLength: int
): ref ForkedSignedBeaconBlock =
  newClone ForkedSignedBeaconBlock(
    kind: ConsensusFork.Gloas,
    gloasData: gloas.SignedBeaconBlock(
      message: gloas.BeaconBlock(
        slot: slot,
        parent_root: parentRoot,
        body: gloas.BeaconBlockBody(
          signed_execution_payload_bid: gloas.SignedExecutionPayloadBid(
            message: gloas.ExecutionPayloadBid(
              blob_kzg_commitments: genKzgCommitments(commitmentsLength))))),
      root: root))

func createGloasEnvelope(
    slot: Slot,
    root: Eth2Digest,
    parentRoot: Eth2Digest
): ref gloas.SignedExecutionPayloadEnvelope =
  newClone gloas.SignedExecutionPayloadEnvelope(
    message: gloas.ExecutionPayloadEnvelope(
      beacon_block_root: root,
      parent_beacon_block_root: parentRoot,
      payload: gloas.ExecutionPayload(slot_number: slot)))

func createGloasItem(
    slot: Slot,
    root: Eth2Digest,
    parentRoot: Eth2Digest,
    commitmentsLength: int,
    env: int
): SyncResponseItem =
  let
    blck = createGloasBlock(slot, root, parentRoot, commitmentsLength)
    envelope =
      if env == 0:
        nil
      else:
        createGloasEnvelope(slot, root, parentRoot)
  SyncResponseItem.init(blck, envelope)

func createGloasItemChain(
    items: openArray[GloasBlockChainResultItem]
): seq[SyncResponseItem] =
  var res: seq[SyncResponseItem]
  for item in items:
    let
      blockRoot = createDigest(item.root)
      blockParentRoot = createDigest(item.parentRoot)
    res.add(
      createGloasItem(
        Slot(item.slot), blockRoot, blockParentRoot, item.commitments,
        item.env))
  res

func createForkedBlock(
    fork: ConsensusFork,
    slot: Slot,
    root: Eth2Digest,
    parentRoot: Eth2Digest
): ref ForkedSignedBeaconBlock =
  withConsensusFork(fork):
    newClone ForkedSignedBeaconBlock.init(
      SignedBeaconBlock(consensusFork)(
        message: BeaconBlock(consensusFork)(
          slot: slot, parent_root: parentRoot),
        root: root))

func createGloasBlockChain(
    items: openArray[GloasBlockChainItem]
): seq[ref ForkedSignedBeaconBlock] =
  var res: seq[ref ForkedSignedBeaconBlock]
  for item in items:
    let
      blockRoot = createDigest(item.root)
      blockParentRoot = createDigest(item.parentRoot)

    if item.fork == ConsensusFork.Gloas:
      res.add(createGloasBlock(
        Slot(item.slot), blockRoot, blockParentRoot, item.commitments))
    else:
      res.add(createForkedBlock(
        item.fork, Slot(item.slot), blockRoot, blockParentRoot))
  res

func createGloasEnvelopeChain(
    items: openArray[GloasEnvelopeChainItem]
): seq[ref gloas.SignedExecutionPayloadEnvelope] =
  var res: seq[ref gloas.SignedExecutionPayloadEnvelope]
  for item in items:
    let
      blockRoot = createDigest(item.root)
      blockParentRoot = createDigest(item.parentRoot)
    res.add(createGloasEnvelope(Slot(item.slot), blockRoot, blockParentRoot))
  res

func createBlockChain(
    slots: openArray[Slot]
): seq[ref ForkedSignedBeaconBlock] =
  var
    res: seq[ref ForkedSignedBeaconBlock]
    root = 0

  for slot in slots:
    let item = newClone ForkedSignedBeaconBlock(kind: ConsensusFork.Fulu)
    item[].fuluData.message.slot = slot
    if root == 0:
      item[].fuluData.root = createDigest(1)
      item[].fuluData.message.parent_root = createDigest(0)
      inc(root)
    else:
      let prev_root = root
      inc(root)
      item[].fuluData.root = createDigest(root)
      item[].fuluData.message.parent_root = createDigest(prev_root)
    res.add(item)
  res

func compareBlock(a, b: ref ForkedSignedBeaconBlock): bool =
  if isNil(a) and isNil(b):
    return true
  if isNil(a) and not(isNil(b)) or (isNil(b) and not(isNil(a))):
    return false
  let
    abid = a[].toBlockHid()
    bbid = b[].toBlockHid()
  if a[].kind != b[].kind:
    return false
  if abid.slot != bbid.slot:
    return false
  if abid.root != bbid.root:
    return false
  true

func compareEnvelope(a, b: ref gloas.SignedExecutionPayloadEnvelope): bool =
  if isNil(a) and isNil(b):
    return true
  if isNil(a) and not(isNil(b)) or (isNil(b) and not(isNil(a))):
    return false
  let
    abid = a[].toEnvelopeHid()
    bbid = b[].toEnvelopeHid()
  if abid.slot != bbid.slot:
    return false
  if abid.root != bbid.root:
    return false
  true

func compareResponseItem(a, b: openArray[SyncResponseItem]): bool =
  if len(a) != len(b):
    return false
  if len(a) == 0:
    return true
  for index, value in a.pairs():
    if not(compareBlock(value.signedBlock, b[index].signedBlock)):
      return false
    if not(compareEnvelope(value.signedEnvelope, b[index].signedEnvelope)):
      return false
  true

suite "Response utilities test suite":

  test "checkResponse() test":
    let
      r1 = SyncRange.init(Slot(11), 1'u64)
      r2 = SyncRange.init(Slot(11), 2'u64)
      r3 = SyncRange.init(Slot(11), 3'u64)
      r4 = SyncRange.init(Slot(11), 4'u64)
      fork = ConsensusFork.Fulu

    check:
      checkResponse(r1, fork,
        createBlockChain([Slot(11)])).isOk() == true
      checkResponse(r1, fork,
        createBlockChain(@[])).isOk() == true
      checkResponse(r1, fork,
        createBlockChain(@[Slot(11), Slot(11)])).isOk() == false
      checkResponse(r1, fork,
        createBlockChain([Slot(10)])).isOk() == false
      checkResponse(r1, fork,
        createBlockChain([Slot(12)])).isOk() == false

      checkResponse(r2, fork,
        createBlockChain([Slot(11)])).isOk() == true
      checkResponse(r2, fork,
        createBlockChain([Slot(12)])).isOk() == true
      checkResponse(r2, fork,
        createBlockChain(@[])).isOk() == true
      checkResponse(r2, fork,
        createBlockChain([Slot(11), Slot(12)])).isOk() == true
      checkResponse(r2, fork,
        createBlockChain([Slot(12)])).isOk() == true
      checkResponse(r2, fork,
        createBlockChain([Slot(11), Slot(12), Slot(13)])).isOk() == false
      checkResponse(r2, fork,
        createBlockChain([Slot(10), Slot(11)])).isOk() == false
      checkResponse(r2, fork,
        createBlockChain([Slot(10)])).isOk() == false
      checkResponse(r2, fork,
        createBlockChain([Slot(12), Slot(11)])).isOk() == false
      checkResponse(r2, fork,
        createBlockChain([Slot(12), Slot(13)])).isOk() == false
      checkResponse(r2, fork,
        createBlockChain([Slot(13)])).isOk() == false

      checkResponse(r2, fork,
        createBlockChain([Slot(11), Slot(11)])).isOk() == false
      checkResponse(r2, fork,
        createBlockChain([Slot(12), Slot(12)])).isOk() == false

      checkResponse(r3, fork,
        createBlockChain(@[Slot(11)])).isOk() == true
      checkResponse(r3, fork,
        createBlockChain(@[Slot(12)])).isOk() == true
      checkResponse(r3, fork,
        createBlockChain(@[Slot(13)])).isOk() == true
      checkResponse(r3, fork,
        createBlockChain(@[Slot(11), Slot(12)])).isOk() == true
      checkResponse(r3, fork,
        createBlockChain(@[Slot(11), Slot(13)])).isOk() == true
      checkResponse(r3, fork,
        createBlockChain(@[Slot(12), Slot(13)])).isOk() == true
      checkResponse(r3, fork,
        createBlockChain(@[Slot(11), Slot(13), Slot(12)])).isOk() == false
      checkResponse(r3, fork,
        createBlockChain(@[Slot(12), Slot(13), Slot(11)])).isOk() == false
      checkResponse(r3, fork,
        createBlockChain(@[Slot(13), Slot(12), Slot(11)])).isOk() == false
      checkResponse(r3, fork,
        createBlockChain(@[Slot(13), Slot(11)])).isOk() == false
      checkResponse(r3, fork,
        createBlockChain(@[Slot(13), Slot(12)])).isOk() == false
      checkResponse(r3, fork,
        createBlockChain(@[Slot(12), Slot(11)])).isOk() == false

      checkResponse(r3, fork,
        createBlockChain(@[Slot(11), Slot(11), Slot(11)])).isOk() == false
      checkResponse(r3, fork,
        createBlockChain(@[Slot(11), Slot(12), Slot(12)])).isOk() == false
      checkResponse(r3, fork,
        createBlockChain(@[Slot(11), Slot(13), Slot(13)])).isOk() == false
      checkResponse(r3, fork,
        createBlockChain(@[Slot(12), Slot(13), Slot(13)])).isOk() == false
      checkResponse(r3, fork,
        createBlockChain(@[Slot(12), Slot(12), Slot(12)])).isOk() == false
      checkResponse(r3, fork,
        createBlockChain(@[Slot(13), Slot(13), Slot(13)])).isOk() == false
      checkResponse(r3, fork,
        createBlockChain(@[Slot(11), Slot(11)])).isOk() == false
      checkResponse(r3, fork,
        createBlockChain(@[Slot(12), Slot(12)])).isOk() == false
      checkResponse(r3, fork,
        createBlockChain(@[Slot(13), Slot(13)])).isOk() == false

    var
      chain1 = createBlockChain(@[Slot(11), Slot(12), Slot(13), Slot(14)])
      chain2 = createBlockChain(@[Slot(11), Slot(12), Slot(13), Slot(14)])
      chain3 = createBlockChain(@[Slot(11), Slot(12), Slot(13), Slot(14)])
      chain4 = createBlockChain(@[Slot(11), Slot(12), Slot(13), Slot(14)])

    withBlck(chain2[1][]):
      forkyBlck.message.parent_root = Eth2Digest()
    withBlck(chain3[2][]):
      forkyBlck.message.parent_root = Eth2Digest()
    withBlck(chain4[3][]):
      forkyBlck.message.parent_root = Eth2Digest()

    check:
      checkResponse(r4, fork, chain1).isOk() == true
      checkResponse(r4, fork, chain2).isOk() == false
      checkResponse(r4, fork, chain3).isOk() == false
      checkResponse(r4, fork, chain4).isOk() == false

  test "combineResponse() test":
    let TestVectors = [
      (
        Slot(31)..Slot(36),
        default(seq[GloasBlockChainItem]),
        default(seq[GloasEnvelopeChainItem]),
         Result[seq[GloasBlockChainResultItem], string].ok(default(seq[GloasBlockChainResultItem]))
      ),
      (
        Slot(31)..Slot(36),
        @[
          (ConsensusFork.Gloas, 31, 31, 0, 0),
          (ConsensusFork.Gloas, 32, 32, 31, 0),
          (ConsensusFork.Gloas, 33, 33, 32, 0)
        ],
        @[(31, 31, 0), (32, 32, 31), (36, 36, 32)],
         Result[seq[GloasBlockChainResultItem], string].err("Some blocks are missing in range")
      ),
      (
        Slot(31)..Slot(36),
        @[
          (ConsensusFork.Gloas, 32, 32, 31, 0),
          (ConsensusFork.Gloas, 33, 33, 32, 0)
        ],
        @[(31, 31, 0), (32, 32, 31), (36, 36, 32)],
         Result[seq[GloasBlockChainResultItem], string].err("Some blocks are missing in range")
      ),
      (
        Slot(31)..Slot(36),
        @[
          (ConsensusFork.Gloas, 31, 31, 0, 0),
          (ConsensusFork.Gloas, 33, 33, 32, 0)
        ],
        @[(31, 31, 0), (32, 32, 31), (36, 36, 32)],
         Result[seq[GloasBlockChainResultItem], string].err("Some blocks are missing in range")
      ),
      (
        Slot(31)..Slot(36),
        @[
          (ConsensusFork.Gloas, 31, 31, 0, 0),
          (ConsensusFork.Fulu, 32, 32, 31, 1)
        ],
        @[(31, 31, 0), (32, 32, 31)],
         Result[seq[GloasBlockChainResultItem], string].err("Received block from incorrect fork")
      ),
      (
        Slot(31)..Slot(36),
        @[
          (ConsensusFork.Gloas, 31, 31, 0, 0),
          (ConsensusFork.Gloas, 32, 32, 31, 1)
        ],
        @[(31, 31, 0), (32, 33, 31)],
         Result[seq[GloasBlockChainResultItem], string].err("The root of the block and the root of the envelope do not match")
      ),
      (
        Slot(31)..Slot(36),
        @[
          (ConsensusFork.Gloas, 31, 31, 0, 0),
          (ConsensusFork.Gloas, 32, 32, 31, 1)
        ],
        @[(31, 31, 0), (32, 32, 30)],
         Result[seq[GloasBlockChainResultItem], string].err("The parent root of the envelope and the root of the parent envelope do not match")
      ),
      (
        Slot(31)..Slot(36),
        @[
          (ConsensusFork.Gloas, 33, 33, 0, 0),
          (ConsensusFork.Gloas, 34, 34, 33, 0)
        ],
        @[(33, 33, 0), (34, 34, 33)],
         Result[seq[GloasBlockChainResultItem], string].ok(
          @[
            (ConsensusFork.Gloas, 33, 33, 0, 0, 1),
            (ConsensusFork.Gloas, 34, 34, 33, 0, 1)
          ])
      ),
      (
        Slot(31)..Slot(36),
        @[
          (ConsensusFork.Gloas, 31, 31, 0, 1),
          (ConsensusFork.Gloas, 32, 32, 31, 0),
          (ConsensusFork.Gloas, 33, 33, 32, 0),
          (ConsensusFork.Gloas, 34, 34, 33, 1),
          (ConsensusFork.Gloas, 35, 35, 34, 0),
          (ConsensusFork.Gloas, 36, 36, 35, 0)
        ],
        @[(31, 31, 0), (34, 34, 33)],
         Result[seq[GloasBlockChainResultItem], string].ok(
          @[
            (ConsensusFork.Gloas, 31, 31, 0, 1, 1),
            (ConsensusFork.Gloas, 32, 32, 31, 0, 0),
            (ConsensusFork.Gloas, 33, 33, 32, 0, 0),
            (ConsensusFork.Gloas, 34, 34, 33, 1, 1),
            (ConsensusFork.Gloas, 35, 35, 34, 0, 0),
            (ConsensusFork.Gloas, 36, 36, 35, 0, 0)
          ])
      ),

    ]

    for vector in TestVectors:
      let res = combineResponse(
        SyncRange.init(vector[0]),
        createGloasBlockChain(vector[1]),
        createGloasEnvelopeChain(vector[2]))
      if res.isOk():
        check vector[3].isOk()
        let chain = createGloasItemChain(vector[3].get())
        check compareResponseItem(chain, res.get())
      else:
        check:
          vector[3].isErr()
          vector[3].error == res.error
