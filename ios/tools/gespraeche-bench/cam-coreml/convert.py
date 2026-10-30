from pathlib import Path
import onnx,torch,coremltools as ct
from onnx2torch import convert
# Der Export verliert nach Reshape die Rank-Metadaten. Alle unbekannten BN-/Pool-
# Eingaben dieses Modells sind 1D-Sequenzen (die finale BN ist ebenfalls BatchNorm1d).
from onnx2torch.node_converters.batch_norm import _BN_CLASS_FROM_SPATIAL_RANK
from onnx2torch.node_converters.average_pool import _AVGPOOL_CLASS_FROM_SPATIAL_RANK
_BN_CLASS_FROM_SPATIAL_RANK[-2] = torch.nn.BatchNorm1d
_AVGPOOL_CLASS_FROM_SPATIAL_RANK[-2] = torch.nn.AvgPool1d
torch.manual_seed(0)
p=str(Path.home()/'paply-gsp-bench/models/3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx')
m=onnx.load(p)
print([(i.name,str(i.type)) for i in m.graph.input],flush=True)
from onnxsim import simplify
m,ok=simplify(m,overwrite_input_shapes={"x":[1,800,80]})
assert ok
onnx.save(m,"/tmp/paply-gsp-d-cam-fixed.onnx")
t=convert(m).eval()
x=torch.randn(1,800,80)
y=t(x)
print('converted',y.shape,flush=True)
traced=torch.jit.trace(t,x)
model=ct.convert(traced,skip_model_load=True,inputs=[ct.TensorType(name='features',shape=x.shape)],minimum_deployment_target=ct.target.iOS18)
model.save(str(Path.home()/'paply-gsp-bench/CAMPlus.mlpackage'))
