express = require('express');
const app = express();
const port = 6006;
app.get('/', (req, res) => res.send('Hello World!'));
app.use(express.static('static'));
app.listen(port, () => console.log('Example app listening on port 6006!'));
